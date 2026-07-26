on mouseUp
  global soundspath
  if sprite(35).visible = 1 then
    sound stop 2
    sound playFile 1, soundspath & "brjsub.aif"
    play frame "brjtalk2"
  end if
end
