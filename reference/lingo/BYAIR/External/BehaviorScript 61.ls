on mouseUp
  global guard, soundspath
  if guard = 0 then
    sound playFile 1, soundspath & "guard1.aif"
    play frame "guardspk"
    sound playFile 1, soundspath & "guard2.aif"
    play frame "hezspkguard"
    sound playFile 1, soundspath & "guard3.aif"
    play frame "guardspk"
    guard = 1
  else
    if guard = 1 then
      sound playFile 1, soundspath & "guard4.aif"
      play frame "guardspk"
      sound playFile 1, soundspath & "guard5.aif"
      play frame "hezspkguard"
      guard = 2
    else
      sound playFile 1, soundspath & "guard6.aif"
      play frame "guardspk"
    end if
  end if
end
