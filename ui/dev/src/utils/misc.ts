/**
 * Will return whether the current environment is in a regular browser and not CEF.
 * @returns {boolean} True if the environment is a regular browser, false if CEF.
 */
export const isEnvBrowser = (): boolean => !window.invokeNative;

/**
 * Basic no operation function.
 */
export const noop = (): void => {};

export function getFormattedDate() {
  const options: Intl.DateTimeFormatOptions = {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  };

  const formattedDate = new Intl.DateTimeFormat("default", options).format(
    new Date()
  );

  return formattedDate;
}
