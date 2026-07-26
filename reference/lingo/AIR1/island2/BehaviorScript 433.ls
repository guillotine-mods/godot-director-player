on exitFrame
  global globalday, wreck
  if (globalday = 3) and (item 12 of wreck = "0") then
    go(1, "figtair.dir")
  end if
end
