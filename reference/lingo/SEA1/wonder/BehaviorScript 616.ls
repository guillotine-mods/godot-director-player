on mouseUp
  global soundspath, wreck
  if sprite(35).visible = 1 then
    sound stop 2
    sound playFile 1, soundspath & "brjcnn.aif"
    play frame "brjtalk2"
  else
    if item 5 of wreck = "done" then
      sound playFile 1, soundspath & "hezfire1.aif"
    end if
  end if
end
