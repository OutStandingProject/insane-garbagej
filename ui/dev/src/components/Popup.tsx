import React, { ReactNode } from "react";
import classNames from "classnames";
import { IoIosClose } from "react-icons/io";
import { FaInfoCircle } from "react-icons/fa";

interface PopupProps {
  isOpen: boolean;
  onClose: () => void;
  children: ReactNode;
  title?: string;
  error?: string;
}

const Popup: React.FC<PopupProps> = ({
  isOpen,
  onClose,
  children,
  title,
  error,
}) => {
  return (
    <div
      className={classNames(
        "fixed inset-0 flex items-center justify-center bg-black bg-opacity-50",
        { hidden: !isOpen }
      )}
    >
      <div className="relative bg-dark p-6 rounded-lg shadow-lg w-96 border border-white/15">
        <div className="flex items-center gap-2">
          <FaInfoCircle className="w-5 h-5" />
          {title && <h2 className="text-xl font-bold">{title}</h2>}
        </div>
        <hr className="border-white/15 my-3" />
        <div>{children}</div>
        <button
          onClick={onClose}
          className="absolute top-2 right-2 opacity-50 hover:opacity-100 transition-opacity"
        >
          <IoIosClose className="w-6 h-6" />
        </button>
        {error && (
          <div className="mt-3 -mb-3">
            <h1 className="text-[#FF6153] text-sm">{error}</h1>
          </div>
        )}
      </div>
    </div>
  );
};

export default Popup;
