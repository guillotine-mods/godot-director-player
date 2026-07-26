on exitFrame
  global soundspath, foe
  put 1 + value(the text of field "hezscore") into field "hezscore"
  if value(the text of field "hezscore") >= 3 then
    go("hezwin")
  else
    x = random(3)
    if x = 1 then
      sound playFile 1, soundspath & "sflhez" & random(10) & ".aif"
      play frame "spkhez"
    else
      if (x = 2) or (x = 3) then
        sound playFile 1, soundspath & "sfl" & item 3 of foe & random(3) & ".aif"
        play frame "spk"
      end if
    end if
  end if
end
