import { useContext } from 'react';
import { useI18n } from '@18f/identity-react-i18n';
import {
  FormStepComponentProps,
  FormStepsButton,
  FormStepsContext,
} from '@18f/identity-form-steps';
import { PageHeading } from '@18f/identity-components';
import { Cancel } from '@18f/identity-verify-flow';
import HybridDocCaptureWarning from './hybrid-doc-capture-warning';
import DocumentSideAcuantCapture from './document-side-acuant-capture';
import UploadContext from '../context/upload';
import TipList from './tip-list';
import { FeatureFlagContext } from '../context';
import DocumentCaptureAbandon from './document-capture-abandon';

export function DocumentCaptureSubheaderOne({
  selfieCaptureEnabled,
}: {
  selfieCaptureEnabled: boolean;
}) {
  const { t } = useI18n();
  return (
    <h2>
      {selfieCaptureEnabled && '1. '}
      {t('doc_auth.headings.document_capture_subheader_id')}
    </h2>
  );
}

export function SelfieCaptureWithHeader({
  defaultSideProps,
  selfieValue,
}: {
  defaultSideProps: DefaultSideProps;
  selfieValue: ImageValue;
}) {
  const { t } = useI18n();
  return (
    <>
      <hr className="margin-y-5" />
      <h2>2. {t('doc_auth.headings.document_capture_subheader_selfie')}</h2>
      <TipList
        title={t('doc_auth.tips.document_capture_selfie_selfie_text')}
        titleClassName="margin-bottom-0 text-bold"
        items={[
          t('doc_auth.tips.document_capture_selfie_text1'),
          t('doc_auth.tips.document_capture_selfie_text2'),
          t('doc_auth.tips.document_capture_selfie_text3'),
        ]}
      />
      <DocumentSideAcuantCapture
        {...defaultSideProps}
        key="selfie"
        side="selfie"
        value={selfieValue}
      />
    </>
  );
}

type ImageValue = Blob | string | null | undefined;

interface DocumentsStepValue {
  front: ImageValue;
  back: ImageValue;
  selfie: ImageValue;
  front_image_metadata?: string;
  back_image_metadata?: string;
}

type DefaultSideProps = Pick<
  FormStepComponentProps<DocumentsStepValue>,
  'registerField' | 'onChange' | 'errors' | 'onError'
>;

function SelfieStep({
  value = {},
  onChange = () => {},
  errors = [],
  onError = () => {},
  registerField = () => undefined,
}: FormStepComponentProps<DocumentsStepValue>) {
  const { t } = useI18n();
  const { isLastStep } = useContext(FormStepsContext);
  const { flowPath } = useContext(UploadContext);
  const { exitQuestionSectionEnabled, selfieCaptureEnabled } = useContext(FeatureFlagContext);

  const pageHeaderText = selfieCaptureEnabled
    ? t('doc_auth.headings.document_capture_with_selfie')
    : t('doc_auth.headings.document_capture');

  const defaultSideProps: DefaultSideProps = {
    registerField,
    onChange,
    errors,
    onError,
  };
  return (
    <>
      {flowPath === 'hybrid' && <HybridDocCaptureWarning className="margin-bottom-4" />}
      <PageHeading>{pageHeaderText}</PageHeading>
      <DocumentCaptureSubheaderOne selfieCaptureEnabled={selfieCaptureEnabled} />
      <SelfieCaptureWithHeader defaultSideProps={defaultSideProps} selfieValue={value.selfie} />
      {isLastStep ? <FormStepsButton.Submit /> : <FormStepsButton.Continue />}
      {exitQuestionSectionEnabled && <DocumentCaptureAbandon />}
      <Cancel />
    </>
  );
}

export default SelfieStep;
