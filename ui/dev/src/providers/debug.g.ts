import { iProfile, iLobby, iTask, iRank } from "@/types/BasicTypes";
import { debugData } from "@/utils/debugData";

debugData([
  {
    action: "ui:setupUI",
    data: {
      setLocale: {
        job_pad: "JobPad",
        file: "File",
        image: "Image",
        order: "Order",
        history: "History",
        place: "Place",
        place_marks: "Place Marks",
        screen: "Screen",
        help: "Help",
        app_title: "Garbage App",
        app_title_delivery: "Delivery App",
        app_title_towtruck: "Towtruck App",
        search: "Search",
        total_reputation: "Total Reputation",
        level: "Level",
        reputation: "Reputation",
        garbage_about: "Garbage About",
        victor_goods: "Victor Goods",
        desc_garbage_about:
          "Street cleaning involves collecting trash from urban areas. Proper waste management prevents environmental degradation and promotes sustainability. The script simulates this process. By actively cleaning the streets, players contribute to a cleaner virtual world.",
        update_photo: "Update Profile Photo",
        save: "Save",
        invite: "Invite",
        player_id: "Player Id",
        maps: "Maps",
        title: "Title",
        rewards: "Rewards",
        rep: "Rep",
        gps: "Gps",
        money_type: "$",
        progress: "Progress",
        clean_dumpster: "Clear Dumpster",
        clean_bin_bag: "Collect Bin Bag",
        continue_task: "Continue Task",
        your_garbage_team: "Your Garbage Team",
        name: "Name",
      },
    },
  },
  {
    action: "ui:setUserProfile",
    data: {
      source: 1,
      exp: 24,
      level: 1,
      nextLevelExp: 400,
      photo: 7,
    } as iProfile,
  },
  { action: "ui:setDebug" },
  {
    action: "ui:setTasks",
    data: [
      {
        unique_id: 1,
        title: "Task #1",
        exp: 200,
        fee: 2500,
        max_client: 4,
        level: 1,
      },
    ] as iTask[],
  },
  {
    action: "ui:setCurrentLobby",
    data: {
      // id: 1,
      members: [
        { photo: 7, source: 1 },
        { photo: 2, source: 2 },
      ],
      leaderId: 2,
      isTaskStarted: true,
      taskId: 1,
      taskProgress: 0,
      goals: 3,
    } as iLobby,
  },
  {
    action: "ui:setRanks",
    data: [
      {
        characterName: "Ali",
        exp: 10000,
        level: 2,
        photo: 1,
        identifier: "",
      },
    ] as iRank[],
  },
] as any);
