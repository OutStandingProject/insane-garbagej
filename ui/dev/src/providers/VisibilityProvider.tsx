import React, { useEffect, useMemo, useState } from "react";
import { useNuiEvent } from "@/hooks/useNuiEvent";
import classNames from "classnames";
import { debugData } from "@/utils/debugData";
import { isEnvBrowser } from "@/utils/misc";
import { fetchNui } from "@/utils/fetchNui";
import { VisibilityCtx } from "./VisibilityContext";

debugData([{ action: "ui:setVisible", data: true }]);

export const VisibilityProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!visible) return;
    const keyHandler = (e: KeyboardEvent) => {
      if (!isEnvBrowser() && ["Escape"].includes(e.code)) {
        fetchNui("nui:hideFrame", true, true);
      }
    };
    window.addEventListener("keydown", keyHandler);
    return () => window.removeEventListener("keydown", keyHandler);
  }, [visible]);

  useNuiEvent<boolean>("ui:setVisible", setVisible);

  const value = useMemo(() => {
    return {
      visible,
      setVisible,
    };
  }, [visible]);

  return (
    <VisibilityCtx.Provider value={value}>
      <main
        className={classNames("w-full h-screen", {
          "bg-black/75": isEnvBrowser(),
        })}
      >
        {children}
      </main>
    </VisibilityCtx.Provider>
  );
};
