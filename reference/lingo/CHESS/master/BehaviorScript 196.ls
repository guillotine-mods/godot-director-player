on exitFrame
  global soundspath, globalday
  sound playFile 1, soundspath & "arti" & random(10) & ".aif"
  if globalday = 2 then
    put "done" into item 8 of line 2 of field "Dprocess" of castLib "master"
  end if
end
