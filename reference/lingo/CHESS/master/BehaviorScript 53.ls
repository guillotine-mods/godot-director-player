on exitFrame
  if rollOver(4) then
    set the visible of sprite 8 to 0
    set the visible of sprite 9 to 0
    set the visible of sprite 7 to 1
  else
    if rollOver(5) then
      set the visible of sprite 8 to 1
      set the visible of sprite 9 to 0
      set the visible of sprite 7 to 0
    else
      if rollOver(6) then
        set the visible of sprite 8 to 0
        set the visible of sprite 9 to 1
        set the visible of sprite 7 to 0
      else
        set the visible of sprite 8 to 0
        set the visible of sprite 9 to 0
        set the visible of sprite 7 to 0
      end if
    end if
  end if
  go(the frame)
end
