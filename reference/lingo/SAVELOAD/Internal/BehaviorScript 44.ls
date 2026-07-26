on exitFrame
  go(marker(0))
  if rollOver(24) then
    set the locH of sprite 31 to the locH of sprite 24
  else
    if rollOver(25) then
      set the locH of sprite 31 to the locH of sprite 25
    else
      if rollOver(26) then
        set the locH of sprite 31 to the locH of sprite 26
      else
        if rollOver(27) then
          set the locH of sprite 31 to the locH of sprite 27
        else
          if rollOver(28) then
            set the locH of sprite 31 to the locH of sprite 28
          else
            if rollOver(29) then
              set the locH of sprite 31 to the locH of sprite 29
            else
              if rollOver(30) then
                set the locH of sprite 31 to the locH of sprite 30
              end if
            end if
          end if
        end if
      end if
    end if
  end if
  updateStage()
end
