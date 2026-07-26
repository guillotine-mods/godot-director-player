on exitFrame
  global zigi, soundspath
  zigi = zigi - 1
  if zigi = 0 then
    set the memberNum of sprite 7 to the number of member "gundefault" of castLib 1
    set the locH of sprite 7 to 175
    set the locV of sprite 7 to 237
    updateStage()
  end if
  if the memberNum of sprite 7 = the number of member "gunup" then
    repeat with i = 8 to 18
      if (((the locV of sprite 7 - the locV of sprite i) > 20) and ((the locH of sprite 7 - the locH of sprite i) < 40) and ((the locH of sprite 7 - the locH of sprite i) > -40) and (the visible of sprite i = 1)) or (the visible of sprite (i + 15) = 1) then
        if not soundBusy(1) then
          sound playFile 1, soundspath & "foe" & random(5) & ".aif"
        end if
        set the visible of sprite i to 0
        set the visible of sprite (i + 15) to 1
        next repeat
      end if
      set the visible of sprite (i + 15) to 0
    end repeat
  else
    if the memberNum of sprite 7 = the number of member "gunright" then
      repeat with i = 8 to 18
        if (((the locV of sprite 7 - the locV of sprite i) < 100) and ((the locH of sprite i - the locH of sprite 7) > 20) and ((the locH of sprite i - the locH of sprite 7) < 150) and (the visible of sprite i = 1)) or (the visible of sprite (i + 15) = 1) then
          if not soundBusy(1) then
            sound playFile 1, soundspath & "foe" & random(5) & ".aif"
          end if
          set the visible of sprite i to 0
          set the visible of sprite (i + 15) to 1
          next repeat
        end if
        set the visible of sprite (i + 15) to 0
      end repeat
    end if
  end if
end
