import {
  VisibilityCtx,
  VisibilityProviderValue,
} from "@/providers/VisibilityContext";
import { useContext } from "react";

export const useVisibility = (): VisibilityProviderValue =>
  useContext<VisibilityProviderValue>(VisibilityCtx);
