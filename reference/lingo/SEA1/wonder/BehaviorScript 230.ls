on exitFrame
  if rollOver(10) then
    set the visible of sprite 3 to 0
    set the visible of sprite 4 to 1
    set the visible of sprite 5 to 0
    set the visible of sprite 6 to 0
  else
    if rollOver(11) then
      set the visible of sprite 3 to 0
      set the visible of sprite 4 to 0
      set the visible of sprite 5 to 0
      set the visible of sprite 6 to 1
    else
      if rollOver(12) then
        set the visible of sprite 3 to 1
        set the visible of sprite 4 to 0
        set the visible of sprite 5 to 0
        set the visible of sprite 6 to 0
      else
        if rollOver(13) then
          set the visible of sprite 3 to 0
          set the visible of sprite 4 to 0
          set the visible of sprite 5 to 1
          set the visible of sprite 6 to 0
        else
          set the visible of sprite 3 to 0
          set the visible of sprite 4 to 0
          set the visible of sprite 5 to 0
          set the visible of sprite 6 to 0
        end if
      end if
    end if
  end if
end
