on exitFrame
  global catgame, soundspath
  repeat with i = 40 to 45
    set the visible of sprite i to 0
  end repeat
  case catgame of
    "paper":
      set the visible of sprite 43 to 1
    "sciser":
      set the visible of sprite 44 to 1
    "stone":
      set the visible of sprite 45 to 1
  end case
  t = random(3)
  if t = 1 then
    set the visible of sprite 40 to 1
    case catgame of
      "paper":
        catgame = "winpper"
      "sciser":
        catgame = "losscsr"
      "stone":
        catgame = "2stone"
    end case
  else
    if t = 2 then
      set the visible of sprite 41 to 1
      case catgame of
        "paper":
          catgame = "lospper"
        "sciser":
          catgame = "2scisr"
        "stone":
          catgame = "winston"
      end case
    else
      set the visible of sprite 42 to 1
      case catgame of
        "paper":
          catgame = "2paper"
        "sciser":
          catgame = "winscsr"
        "stone":
          catgame = "losston"
      end case
    end if
  end if
  sound playFile 1, soundspath & "suspense.aif"
end
