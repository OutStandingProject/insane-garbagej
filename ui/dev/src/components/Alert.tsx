import React from "react";

interface AlertProps {
  message: string;
}

const Alert: React.FC<AlertProps> = ({ message }) => {
  return (
    <div
      id="alert-2"
      className="fixed right-2 top-32 flex items-center py-3 px-10 mb-4 rounded bg-gray-800 text-red-500 border border-white/10"
      role="alert"
    >
      <svg
        className="flex-shrink-0 w-4 h-4"
        aria-hidden="true"
        xmlns="http://www.w3.org/2000/svg"
        fill="currentColor"
        viewBox="0 0 20 20"
      >
        <path d="M10 .5a9.5 9.5 0 1 0 9.5 9.5A9.51 9.51 0 0 0 10 .5ZM9.5 4a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM12 15H8a1 1 0 0 1 0-2h1v-3H8a1 1 0 0 1 0-2h2a1 1 0 0 1 1 1v4h1a1 1 0 0 1 0 2Z" />
      </svg>
      <div className="ms-2 text-sm font-d_kallisto">{message}</div>
    </div>
  );
};

export default Alert;
