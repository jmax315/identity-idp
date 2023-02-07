module InPerson
  class IppLocationsCacherJob < ApplicationJob
    include ArcgisApi

    def perform(post_offices)
      post_offices.each do |location|
        location = Geocoder.new.find_address_candidates(
          Address: location[:address],
          City: location[:city],
          Region: location[:state],
          Postal: location[:zip_code_5],
        ).first.location

        UspsIppCachedLocations.create!(
          lonlat: RGeo::Geos.factory(srid: 4326).point(location.longitude, location.latitude),
          usps_attributes: location
        )
      end
    end
  end
end
