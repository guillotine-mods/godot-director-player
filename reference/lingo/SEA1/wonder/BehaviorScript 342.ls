on exitFrame
  global dubi, ifmovie, nextroomdata, wreck
  set the visible of sprite 21 to 1
  if dubi < 2 then
    set the visible of sprite 14 to 1
  else
    set the visible of sprite 14 to 0
  end if
  if item 4 of wreck = "done" then
    set the visible of sprite 22 to 1
    set the visible of sprite 23 to 1
    set the visible of sprite 24 to 1
    set the visible of sprite 29 to 0
  else
    set the visible of sprite 22 to 0
    set the visible of sprite 23 to 0
    set the visible of sprite 24 to 0
    set the visible of sprite 29 to 1
  end if
  ifmovie = "0,0"
  put "hall1" into item 1 of nextroomdata
  go("fromware")
end
