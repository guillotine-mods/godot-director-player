on exitFrame
  repeat with i = 1 to 40
    set the visible of sprite i to 1
  end repeat
  set the visible of sprite 9 to 0
  go("wreckgo")
end
