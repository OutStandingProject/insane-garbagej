import { DataCtx } from "@/providers/DataContext";
import { useContext } from "react";

const useData = () => {
  const dataContext = useContext(DataCtx);
  return dataContext;
};

export default useData;
