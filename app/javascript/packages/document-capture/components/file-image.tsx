import { useContext, useState, useEffect } from 'react';
import { useIfStillMounted } from '@18f/identity-react-hooks';
import FileBase64CacheContext from '../context/file-base64-cache';

interface FileImageProps {
  /**
   * Callback triggered on step change.
   */
  // onStepChange?: () => void;
  file: Blob; // Image file.
  alt: string; // Image alt text.
  className?: string; // class name.
}

interface targetResultProps{
  result?: string;
}

interface targetProps{
  target: targetResultProps | undefined;
}

function FileImage({ file, alt, className }: FileImageProps) {
  const cache = useContext(FileBase64CacheContext);
  const [, forceRender] = useState(/** @type {number=} */ (undefined));
  const imageData = cache.get(file);
  const ifStillMounted = useIfStillMounted();

  useEffect(() => {
    const reader = new window.FileReader();
    reader.onload = ({ target }: targetProps) => {
      cache.set(file, target ? target.result : "");
      ifStillMounted(forceRender)((prevState = 0) => 1 - prevState);
    };
    reader.readAsDataURL(file);
  }, [file]);

  const classes = [
    'document-capture-file-image',
    !imageData && 'document-capture-file-image--loading',
    className,
  ]
    .filter(Boolean)
    .join(' ');

  return imageData ? (
    <img src={imageData} alt={alt} className={classes} />
  ) : (
    <span className={classes} />
  );
}

export default FileImage;
