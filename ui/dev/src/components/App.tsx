import React from "react";
import useData from "@/hooks/useData";
import { AppTypes } from "@/types/BasicTypes";
import Tablet from "./Tablet";
import ShortcutGarbage from "./Shortcut/Garbage";
import ShortcutDelivery from "./Shortcut/Delivery";
import ShortcutTowtruck from "./Shortcut/Towtruck";
import BoilerPlate from "./App/BoilerPlate";
import AppGarbage from "@/pages/Garbage";
import { fetchNui } from "@/utils/fetchNui";
import { useVisibility } from "@/hooks/useVisibility";
import { useTranslation } from "react-i18next";

const App: React.FC = () => {
  const { isAppRunning, page, currentLobby, taskInfo, setIsAppRunning } =
    useData();
  const { visible } = useVisibility();
  const { t } = useTranslation();

  const applicationComponents: Record<
    AppTypes,
    { shortcut: React.ReactNode; main: React.ReactNode | (() => void) }
  > = {
    garbage: {
      shortcut: <ShortcutGarbage />,
      main: (
        <BoilerPlate>
          <AppGarbage />
        </BoilerPlate>
      ),
    },
    delivery: {
      shortcut: <ShortcutDelivery />,
      main: () => {
        fetchNui("nui:openBundleApp", "delivery", true);
      },
    },
    towtruck: {
      shortcut: <ShortcutTowtruck />,
      main: () => {
        fetchNui("nui:openBundleApp", "towtruck", true);
      },
    },
  };

  const ApplicationShortcuts = () => (
    <div className="w-full h-full relative pt-6 pl-6 flex flex-col gap-6">
      {Object.keys(applicationComponents).map((key) => (
        <React.Fragment key={key}>
          {applicationComponents[key as AppTypes].shortcut}
        </React.Fragment>
      ))}
    </div>
  );

  const ActiveApplication = () => {
    const key = applicationComponents[page as AppTypes]?.main;

    if (typeof key === "function") {
      key();
      setIsAppRunning(false);
      return <></>;
    } else if (React.isValidElement(key)) {
      return key;
    } else {
      return <></>;
    }
  };

  return (
    <>
      <div
        className="w-full h-full z-10"
        style={{ visibility: visible ? "visible" : "hidden" }}
      >
        <Tablet>
          {!isAppRunning ? <ApplicationShortcuts /> : <ActiveApplication />}
        </Tablet>
      </div>
      {currentLobby.id && currentLobby.isTaskStarted && (
        <div className="absolute bottom-8 left-1/2 -translate-x-1/2 z-0">
          <div className="relative min-w-64 max-w-64 flex flex-col items-center justify-center gap-3">
            <div>
              <h1 className="text-xs font-bold text-FF4747 shadow-FF4747 p-1 px-3 bg-FF4747/10 border border-FF4747/15">
                <span>{t("progress")}</span>
                <span> </span>
                <span>{currentLobby.taskProgress}</span>
                <span>{"/"}</span>
                <span>{currentLobby.goals}</span>
              </h1>
            </div>
            <div className="relative h-0.5 w-full bg-white/15 flex justify-center rounded-3xl">
              <div
                className="absolute h-full w-2/3 bg-FF4747 rounded-3xl
                  shadow-[0_0_3px] shadow-FF4747"
              ></div>
            </div>
            <div className="w-full flex items-center justify-center p-2 bg-white/10 text-center rounded border border-white/25">
              <h1 className="text-xs font-medium">
                {taskInfo ?? t("continue_task")}
              </h1>
            </div>
          </div>
        </div>
      )}
    </>
  );
};

export default App;
