on mouseUp
  global monk, soundspath
  sprite(9).visible = 0
  if the memberNum of sprite 9 = the number of member "monkright" then
    sound stop 2
    sound playFile 1, soundspath & "monk6.aif"
    play frame "teeth"
    sprite(9).visible = 1
  else
    if the memberNum of sprite 9 = the number of member "monkmiddle" then
      sound playFile 1, soundspath & "monk9.aif"
      play frame "speakmiddle1"
      sprite(9).visible = 1
    else
      sound playFile 1, soundspath & "monk10.aif"
      sound stop 2
      play frame "speakleft"
      sprite(9).visible = 1
    end if
  end if
end
