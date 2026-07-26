on exitFrame
  global effectspath
  if (the keyDownScript <> "fromnow") or not soundBusy(2) then
    set the keyDownScript to "fromnow"
    sound stop 1
    set the volume of sound 2 to 255
    sound playFile 2, effectspath & "song1.aif"
  end if
end
