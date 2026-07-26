on exitFrame
  global soundspath, foe
  put value(the text of field "hatscore") + 1 into field "hatscore"
  if value(the text of field "hatscore") >= 3 then
    go("foewin")
  else
    x = random(3)
    if x = 1 then
      sound playFile 1, soundspath & "sflhezb" & random(10) & ".aif"
      play frame "spkhez"
    else
      if (x = 2) or (x = 3) then
        sound playFile 1, soundspath & "sfl" & item 3 of foe & "b" & random(3) & ".aif"
        play frame "spk"
      end if
    end if
  end if
end
