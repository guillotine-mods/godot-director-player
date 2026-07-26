on exitFrame
  global catgame, soundspath
  repeat with i = 40 to 45
    set the visible of sprite i to 0
  end repeat
  set the visible of sprite 46 to 1
  set the visible of sprite 47 to 1
  whowon = "0,0,0"
  if catgame = "top" then
    set the visible of sprite 45 to 1
    put "top" into item 1 of whowon
  else
    set the visible of sprite 44 to 1
    put "bottom" into item 1 of whowon
  end if
  x = random(2)
  if x = 1 then
    set the visible of sprite 41 to 1
    put "top" into item 2 of whowon
  else
    set the visible of sprite 40 to 1
    put "bottom" into item 2 of whowon
  end if
  x = random(2)
  if x = 1 then
    set the visible of sprite 42 to 1
    put "top" into item 3 of whowon
  else
    set the visible of sprite 43 to 1
    put "bottom" into item 3 of whowon
  end if
  sound playFile 1, soundspath & "suspense.aif"
  if item 1 of whowon = item 2 of whowon then
    if item 1 of whowon = item 3 of whowon then
      catgame = "anotherround"
    else
      catgame = "hezwinright"
    end if
  else
    if item 1 of whowon = item 3 of whowon then
      catgame = "hezwinleft"
    else
      catgame = "hezlost"
    end if
  end if
end
