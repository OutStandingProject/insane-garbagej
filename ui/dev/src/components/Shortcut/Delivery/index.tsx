import useData from "@/hooks/useData";
import React from "react";
import { useTranslation } from "react-i18next";

const Delivery: React.FC = () => {
  const { setPage, setIsAppRunning } = useData();
  const { t } = useTranslation();

  const handleClick = (e: React.MouseEvent<HTMLDivElement>) => {
    e.preventDefault();
    setPage("delivery");
    setIsAppRunning(true);
  };

  return (
    <>
      <div
        onClick={handleClick}
        className="flex flex-col items-center cursor-pointer"
        style={{
          width: "84px",
          height: "88px",
        }}
      >
        <div
          style={{
            width: "66px",
            height: "54px",
          }}
        >
          <img src="images/icons/folder.png" alt="app-delivery" />
        </div>
        <div className="text-center mt-1">
          <h1
            className="text-white text-xs font-bold"
            style={{ textShadow: "0px 0px 1.6px rgba(0, 0, 0, 0.85)" }}
          >
            {t("app_title_delivery")}
          </h1>
        </div>
      </div>
    </>
  );
};

export default Delivery;
