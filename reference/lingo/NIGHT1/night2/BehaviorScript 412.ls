on exitFrame
  global globalnight, globalday
  if (item 3 of globalnight = "0") and (globalday = 2) then
    set the visible of sprite 15 to 1
  else
    set the visible of sprite 15 to 0
  end if
end
