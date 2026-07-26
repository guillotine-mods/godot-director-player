on exitFrame
  global foe
  repeat with i = 100 to 109
    set the visible of sprite i to 1
  end repeat
  if item 3 of foe = "end" then
    put "man" into item 3 of foe
  else
    if item 3 of foe <> "man" then
      set the visible of sprite 106 to 0
      set the visible of sprite 107 to 1
    else
      set the visible of sprite 106 to 1
      set the visible of sprite 107 to 0
    end if
  end if
end
