on exitFrame
  global soundspath
  sprite(8).visible = 0
  if item 5 of line 1 of field "Dprocess" = "rotor" then
    sprite(7).visible = 0
  end if
  sound playFile 1, soundspath & "lturn" & random(3) & ".aif"
end
