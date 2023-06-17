module ArcgisApi
  class Geocoder
    Suggestion = Struct.new(:text, :magic_key, keyword_init: true)
    AddressCandidate = Struct.new(
      :address, :location, :street_address, :city, :state, :zip_code,
      keyword_init: true
    )
    Location = Struct.new(:latitude, :longitude, keyword_init: true)

    # These are option URL params that tend to apply to multiple endpoints
    # https://developers.arcgis.com/rest/geocode/api-reference/geocoding-find-address-candidates.htm#ESRI_SECTION2_38613C3FCB12462CAADD55B2905140BF
    COMMON_DEFAULT_PARAMETERS = {
      f: 'json',
      countryCode: 'USA',
      # See https://developers.arcgis.com/rest/geocode/api-reference/geocoding-category-filtering.htm#ESRI_SECTION1_502B3FE2028145D7B189C25B1A00E17B
      #   and https://developers.arcgis.com/rest/geocode/api-reference/geocoding-service-output.htm#GUID-D5C1A6E8-82DE-4900-8F8D-B390C2714A1F
      category: [
        # A subset of a PointAddress that represents a house or building subaddress location,
        #   such as an apartment unit, floor, or individual building within a complex.
        #   E.g. 3836 Emerald Ave, Suite C, La Verne, CA, 91750
        'Subaddress',

        # A street address based on points that represent house and building locations.
        #   E.g. 380 New York St, Redlands, CA, 92373
        'Point Address',

        # A street address that differs from PointAddress because the house number is interpolated
        #   from a range of numbers. E.g. 647 Haight St, San Francisco, CA, 94117
        'Street Address',

        # Similar to a street address but without the house number.
        #   E.g. Olive Ave, Redlands, CA, 92373.
        'Street Name',
      ].join(','),
    }.freeze

    KNOWN_FIND_ADDRESS_CANDIDATES_PARAMETERS = [
      :magicKey, # Generated from /suggest; identifier used to retrieve full address record
      :SingleLine, # Unvalidated address-like text string used to search for geocoded addresses
    ]

    private attr_accessor :token_keeper

    def initialize(token_keeper: TokenKeeper.new)
      @token_keeper = token_keeper
    end

    # Makes an HTTP request to quickly find potential address matches. Each match that is found
    # will include an associated magic_key value which can later be used to get more details about
    # the address using the #find_address_candidates method
    # Requests text input and will only match possible addresses
    # A maximum of 5 suggestions are included in the suggestions array.
    # @param text [String]
    # @return [Array<Suggestion>] Suggestions
    def suggest(text)
      params = {
        text: text,
        **COMMON_DEFAULT_PARAMETERS,
      }

      parse_suggestions(
        connection.
          get(IdentityConfig.store.arcgis_api_suggest_url, params, dynamic_headers) do |req|
          req.options.context = { service_name: 'arcgis_geocoder_suggest' }
        end.body,
      )
    end

    # Makes HTTP request to find a full address record using a magic key or single text line
    # @param options [Hash] one of 'magicKey', which is an ID returned from /suggest,
    #   or 'SingleLine', which should be a single string address that includes at least city
    #   and state.
    # @return [Array<AddressCandidate>] AddressCandidates
    def find_address_candidates(**options)
      supported_params = options.slice(*KNOWN_FIND_ADDRESS_CANDIDATES_PARAMETERS)

      if supported_params.empty?
        raise ArgumentError, <<~MSG
          Unknown parameters: #{options.except(*KNOWN_FIND_ADDRESS_CANDIDATES_PARAMETERS)}.
          See https://developers.arcgis.com/rest/geocode/api-reference/geocoding-find-address-candidates.htm
        MSG
      end

      params = {
        outFields: 'StAddr,City,RegionAbbr,Postal',
        **COMMON_DEFAULT_PARAMETERS,
        **supported_params,
      }

      parse_address_candidates(
        connection.get(
          IdentityConfig.store.arcgis_api_find_address_candidates_url, params, dynamic_headers
        ) do |req|
          req.options.context = { service_name: 'arcgis_geocoder_find_address_candidates' }
        end.body,
      )
    end

    def token
      token_keeper.token
    end

    private

    def connection
      Faraday.new do |conn|
        # Log request metrics
        conn.request :instrumentation, name: 'request_metric.faraday'
        conn.options.timeout = IdentityConfig.store.arcgis_api_request_timeout_seconds
        # Raise an error subclassing Faraday::Error on 4xx, 5xx, and malformed responses
        # Note: The order of this matters for parsing the error response body.
        conn.response :raise_error
        # Parse JSON responses
        conn.response :json, content_type: 'application/json'
        yield conn if block_given?
      end
    end

    def parse_suggestions(response_body)
      handle_api_errors(response_body)

      response_body['suggestions'].map do |suggestion|
        Suggestion.new(
          text: suggestion['text'],
          magic_key: suggestion['magicKey'],
        )
      end
    end

    def parse_address_candidates(response_body)
      handle_api_errors(response_body)

      response_body['candidates'].map do |candidate|
        AddressCandidate.new(
          address: candidate['address'],
          location: Location.new(
            longitude: candidate.dig('location', 'x'),
            latitude: candidate.dig('location', 'y'),
          ),
          street_address: candidate.dig('attributes', 'StAddr'),
          city: candidate.dig('attributes', 'City'),
          state: candidate.dig('attributes', 'RegionAbbr'),
          zip_code: candidate.dig('attributes', 'Postal'),
        )
      end
    end

    # handles API error state when returned as a status of 200
    # @param response_body [Hash]
    def handle_api_errors(response_body)
      if response_body['error']
        # response_body is in this format:
        # {"error"=>{"code"=>400, "message"=>"", "details"=>[""]}}
        error_code = response_body.dig('error', 'code')
        error_message = response_body.dig('error', 'message') || "Received error code #{error_code}"
        # log an error
        analytics.idv_arcgis_request_failure(
          exception_class: 'ArcGIS',
          exception_message: error_message,
          response_body_present: false,
          response_body: '',
          response_status_code: error_code,
          api_status_code: error_code,
        )
        raise Faraday::ClientError.new(
          RuntimeError.new(error_message),
          {
            status: error_code,
            body: { details: response_body.dig('error', 'details')&.join(', ') },
          },
        )
      end
    end

    # Retrieve the short-lived API token (if needed) and then pass
    # the headers to an arbitrary block of code as a Hash.
    #
    # Returns the same value returned by that block of code.
    def dynamic_headers
      { 'Authorization' => "Bearer #{token}" }
    end

    def analytics(user: AnonymousUser.new)
      Analytics.new(user: user, request: nil, session: {}, sp: nil)
    end
  end
end
