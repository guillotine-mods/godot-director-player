on zigiscript
  global zigi, effectspath
  if (the keyCode = 126) or (the keyCode = 13) then
    zigi = 5
    set the memberNum of sprite 7 to the number of member "action1" of castLib 1
    sound playFile 1, effectspath & "jump.aif"
    updateStage()
  else
    if (the keyCode = 124) or (the keyCode = 14) then
      zigi = 4
      set the memberNum of sprite 7 to the number of member "action2" of castLib 1
      sound playFile 1, effectspath & "kick.aif"
      updateStage()
    else
      if (the keyCode = 125) or (the keyCode = 2) then
        zigi = 4
        set the memberNum of sprite 7 to the number of member "action3" of castLib 1
        sound playFile 1, effectspath & "box.aif"
        updateStage()
      end if
    end if
  end if
end

on gun
  global zigi, effectspath
  if (the keyCode = 126) or (the keyCode = 13) then
    zigi = 6
    if the memberNum of sprite 7 <> the number of member "gunup" of castLib 1 then
      set the locH of sprite 7 to the locH of sprite 7 + 33
      set the locV of sprite 7 to the locV of sprite 7 + 12
    end if
    set the memberNum of sprite 7 to the number of member "gunup" of castLib 1
    sound playFile 1, effectspath & "gunup.aif"
    updateStage()
  else
    if (the keyCode = 124) or (the keyCode = 14) then
      zigi = 4
      if the memberNum of sprite 7 <> the number of member "gunright" of castLib 1 then
        set the locH of sprite 7 to the locH of sprite 7 + 54
        set the locV of sprite 7 to the locV of sprite 7 + 37
      end if
      set the memberNum of sprite 7 to the number of member "gunright" of castLib 1
      sound playFile 1, effectspath & "gunright.aif"
      updateStage()
    end if
  end if
end
