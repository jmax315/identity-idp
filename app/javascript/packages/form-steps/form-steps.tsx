import { Suspense, useEffect, useRef, useState } from 'react';
import type { FormEventHandler, RefCallback, FC } from 'react';
import { Alert } from '@18f/identity-components';
import { replaceVariables } from '@18f/identity-i18n';
import { useDidUpdateEffect, useIfStillMounted } from '@18f/identity-react-hooks';
import RequiredValueMissingError from './required-value-missing-error';
import FormStepsContext from './form-steps-context';
import PromptOnNavigate from './prompt-on-navigate';
import useHistoryParam from './use-history-param';
import useForceRender from './use-force-render';

export interface FormStepError<V> {
  /**
   * Name of field for which error occurred.
   */
  field?: keyof V;

  /**
   * Error object.
   */
  error: Error;
}

interface FormStepRegisterFieldOptions {
  /**
   * Whether field is required.
   */
  isRequired: boolean;
}

export type RegisterFieldCallback = (
  field: string,
  options?: Partial<FormStepRegisterFieldOptions>,
) => undefined | RefCallback<HTMLInputElement>;

export type OnErrorCallback = (error: Error, options?: { field?: string | null }) => void;

type FormValues = Record<string, any>;

export interface FormStepComponentProps<V> {
  /**
   * Update values, merging with existing values.
   */
  onChange: (nextValues: Partial<V>) => void;

  /**
   * Trigger a field error.
   */
  onError: OnErrorCallback;

  /**
   * Current values.
   */
  value: Partial<V>;

  /**
   * Current active errors.
   */
  errors: FormStepError<V>[];

  /**
   * Current top-level errors.
   */
  unknownFieldErrors: FormStepError<V>[];

  /**
   * Registers field by given name, returning ref assignment function.
   */
  registerField: RegisterFieldCallback;

  /**
   * Callback to navigate to the previous step.
   */
  toPreviousStep: () => void;
}

export interface FormStep<V extends FormValues = {}> {
  /**
   * Step name, used in history parameter.
   */
  name: string;

  /**
   * Step form component.
   */
  form: FC<FormStepComponentProps<V>>;

  /**
   * Optionally-asynchronous submission behavior, expected to throw any submission error.
   */
  submit?: (values: V) => void | Record<string, any> | Promise<void | Record<string, any>>;

  /**
   * Human-readable step label.
   */
  title?: string;

  /**
   * Callback invoked when the step should preload any dynamically-imported content in anticipation
   * that the step will be reached imminently.
   */
  preload?: () => any;
}

interface FieldsRefEntry {
  /**
   * Ref callback.
   */
  refCallback: RefCallback<HTMLElement>;

  /**
   * Whether field is required.
   */
  isRequired: boolean;

  /**
   * Element assigned by ref callback.
   */
  element: HTMLElement | null;
}

interface FormStepsProps {
  /**
   * Form steps.
   */
  steps?: FormStep<any>[];

  /**
   * Step at which to start form.
   */
  initialStep?: string;

  /**
   * Form values to populate initial state.
   */
  initialValues?: Record<string, any>;

  /**
   * Errors to initialize state.
   */
  initialActiveErrors?: FormStepError<Record<string, Error>>[];

  /**
   * Whether to automatically focus heading on mount.
   */
  autoFocus?: boolean;

  /**
   * Form values change callback.
   */
  onChange?: (values: FormValues) => void;

  /**
   * Form completion callback.
   */
  onComplete?: (values: FormValues) => void;

  /**
   * Callback triggered on step change.
   */
  onStepChange?: (stepName: string) => void;

  /**
   * Callback triggered on step submit.
   */
  onStepSubmit?: (stepName: string) => void;

  /**
   * Whether to prompt the user about unsaved changes when navigating away from an in-progress form.
   * Defaults to true.
   */
  promptOnNavigate?: boolean;

  /**
   * When using path fragments for maintaining history, the base path to which the current step name
   * is appended.
   */
  basePath?: string;

  /**
   * Format string for page title, interpolated with step title as `%{step}` parameter.
   */
  titleFormat?: string;
}

/**
 * React hook which sets page title for the current step.
 *
 * @param step Current step.
 * @param titleFormat Format string for page title.
 */
function useStepTitle(step?: FormStep<any>, titleFormat?: string) {
  useEffect(() => {
    if (titleFormat && step?.title) {
      document.title = replaceVariables(titleFormat, { step: step.title });
    }
  }, [step]);
}

function usePreloadedNextStep(currentStepIndex: number, steps: FormStep<any>[]) {
  const nextStep = steps[currentStepIndex + 1] as FormStep | undefined;
  useEffect(() => {
    if (nextStep && nextStep.preload) {
      nextStep.preload();
    }
  }, [nextStep]);
}

/**
 * Returns the index of the step in the array which matches the given name. Returns `-1` if there is
 * no step found by that name.
 *
 * @param steps Form steps.
 * @param name Step to search.
 *
 * @return Step index.
 */
export function getStepIndexByName(steps: FormStep<any>[], name?: string) {
  return name ? steps.findIndex((step) => step.name === name) : -1;
}

/**
 * Returns the first element matched to a field from a set of errors, if exists.
 *
 * @param errors Active form step errors.
 * @param fields Current fields.
 */
function getFieldActiveErrorFieldElement(
  errors: FormStepError<Record<string, Error>>[],
  fields: Record<string, FieldsRefEntry>,
) {
  const error = errors.find(({ field }) => field && fields[field]?.element);

  if (error) {
    return fields[error.field!].element || undefined;
  }
}

function FormSteps({
  steps = [],
  onChange = () => {},
  onComplete = () => {},
  onStepChange = () => {},
  onStepSubmit = () => {},
  initialStep,
  initialValues = {},
  initialActiveErrors = [],
  autoFocus,
  promptOnNavigate = true,
  basePath,
  titleFormat,
}: FormStepsProps) {
  const [values, setValues] = useState(initialValues);
  const [activeErrors, setActiveErrors] = useState(initialActiveErrors);
  const formRef = useRef(null as HTMLFormElement | null);
  const [stepName, setStepName] = useHistoryParam(initialStep, { basePath });
  const [stepErrors, setStepErrors] = useState([] as Error[]);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const fields = useRef({} as Record<string, FieldsRefEntry>);
  const didSubmitWithErrors = useRef(false);
  const forceRender = useForceRender();
  const ifStillMounted = useIfStillMounted();
  useEffect(() => {
    if (activeErrors.length && didSubmitWithErrors.current) {
      const activeErrorFieldElement = getFieldActiveErrorFieldElement(activeErrors, fields.current);
      if (activeErrorFieldElement) {
        if (activeErrorFieldElement instanceof HTMLInputElement) {
          activeErrorFieldElement.reportValidity();
        }
        activeErrorFieldElement.focus();
      }
    }

    didSubmitWithErrors.current = false;
  }, [activeErrors]);

  const stepIndex = Math.max(getStepIndexByName(steps, stepName), 0);
  const step = steps[stepIndex] as FormStep | undefined;

  /**
   * After a change in content, maintain focus by resetting to the beginning of the new content.
   */
  function onPageTransition() {
    const firstElementChild = formRef.current?.firstElementChild;
    if (firstElementChild instanceof window.HTMLElement) {
      firstElementChild.classList.add('form-steps__focus-anchor');
      firstElementChild.setAttribute('tabindex', '-1');
      firstElementChild.focus();
    }

    setStepName(stepName);
  }

  useStepTitle(step, titleFormat);
  useDidUpdateEffect(() => onStepChange(stepName!), [step]);
  useDidUpdateEffect(onPageTransition, [step]);
  useDidUpdateEffect(() => onChange(values), [values]);
  usePreloadedNextStep(stepIndex, steps);

  useEffect(() => {
    // Treat explicit initial step the same as step transition, placing focus to header.
    if (autoFocus) {
      onPageTransition();
    }
  }, []);

  useEffect(() => {
    if (stepErrors.length) {
      onPageTransition();
    }
  }, [stepErrors]);

  /**
   * Returns array of form errors for the current set of values.
   */
  function getValidationErrors(): FormStepError<Record<string, Error>>[] {
    return Object.keys(fields.current).reduce((result, key) => {
      const { element, isRequired } = fields.current[key];
      const isActive = !!element;

      let error: Error | undefined;
      if (isActive) {
        if (element instanceof HTMLInputElement) {
          element.checkValidity();
        }

        if (element instanceof HTMLInputElement && element.validationMessage) {
          error = new Error(element.validationMessage);
        } else if (isRequired && !values[key]) {
          error = new RequiredValueMissingError();
        }
      }

      if (error) {
        result = result.concat({ field: key, error });
      }

      return result;
    }, [] as FormStepError<Record<string, Error>>[]);
  }

  // An empty steps array is allowed, in which case there is nothing to render.
  if (!step) {
    return null;
  }

  const setPatchValues = (patch: Partial<FormValues>) =>
    setValues((prevValues) => ({ ...prevValues, ...patch }));
  const unknownFieldErrors = activeErrors.filter(
    ({ field }) => !field || !fields.current[field]?.element,
  );
  const hasUnresolvedFieldErrors =
    activeErrors.length && activeErrors.length > unknownFieldErrors.length;
  const { form: Form, submit, name } = step;

  /**
   * Increments state to the next step, or calls onComplete callback if the current step is the last
   * step.
   */
  const toNextStep: FormEventHandler = async (event) => {
    event.preventDefault();

    // Don't proceed if field errors have yet to be resolved.
    if (hasUnresolvedFieldErrors) {
      setActiveErrors(Array.from(activeErrors));
      didSubmitWithErrors.current = true;
      return;
    }

    const nextActiveErrors = getValidationErrors();
    setActiveErrors(nextActiveErrors);
    if (nextActiveErrors.length) {
      didSubmitWithErrors.current = true;
      return;
    }

    if (submit) {
      try {
        setIsSubmitting(true);
        const patchValues = await submit(values);
        if (patchValues) {
          setPatchValues(patchValues);
        }
        setIsSubmitting(false);
      } catch (error) {
        setActiveErrors([{ error }]);
        setIsSubmitting(false);
        return;
      }
    }

    onStepSubmit(step?.name);

    const nextStepIndex = stepIndex + 1;
    const isComplete = nextStepIndex === steps.length;
    if (isComplete) {
      onComplete(values);
    } else {
      const { name: nextStepName } = steps[nextStepIndex];
      setStepName(nextStepName);
    }
  };

  const toPreviousStep = () => {
    const previousStepIndex = Math.max(stepIndex - 1, 0);
    const { name: nextStepName } = steps[previousStepIndex];
    setStepName(nextStepName);
  };

  const isLastStep = stepIndex + 1 === steps.length;

  return (
    <form ref={formRef} onSubmit={toNextStep} noValidate>
      {promptOnNavigate && Object.keys(values).length > 0 && <PromptOnNavigate />}
      {stepErrors.map((error) => (
        <Alert key={error.message} type="error" className="margin-bottom-4">
          {error.message}
        </Alert>
      ))}
      <FormStepsContext.Provider value={{ isLastStep, isSubmitting, onPageTransition }}>
        <Suspense fallback="">
          <Form
            key={name}
            value={values}
            errors={activeErrors}
            unknownFieldErrors={unknownFieldErrors}
            onChange={ifStillMounted((nextValuesPatch) => {
              setActiveErrors((prevActiveErrors) =>
                prevActiveErrors.filter(({ field }) => !field || !(field in nextValuesPatch)),
              );
              setPatchValues(nextValuesPatch);
            })}
            onError={ifStillMounted((error, { field } = {}) => {
              if (field) {
                setActiveErrors((prevActiveErrors) => prevActiveErrors.concat({ field, error }));
              } else {
                setStepErrors([error]);
              }
            })}
            registerField={(field, options = {}) => {
              if (!fields.current[field]) {
                fields.current[field] = {
                  refCallback(fieldNode) {
                    fields.current[field].element = fieldNode;

                    if (activeErrors.length) {
                      forceRender();
                    }
                  },
                  element: null,
                  isRequired: !!options.isRequired,
                };
              }

              return fields.current[field].refCallback;
            }}
            toPreviousStep={toPreviousStep}
          />
        </Suspense>
      </FormStepsContext.Provider>
    </form>
  );
}

export default FormSteps;
