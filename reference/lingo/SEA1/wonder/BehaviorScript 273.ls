on exitFrame
  repeat with i = 3 to 6
    set the visible of sprite i to 0
    set the visible of sprite (i + 13) to 0
  end repeat
  set the visible of sprite 17 to 1
  go("map")
end
