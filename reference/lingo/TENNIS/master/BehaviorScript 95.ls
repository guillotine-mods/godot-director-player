on exitFrame
  global effectspath
  set the keyDownScript to EMPTY
  set the memberNum of sprite 7 to the number of member "hezstnd"
  puppetSprite(9, 0)
  sound playFile 1, effectspath & "tball" & random(2) & ".aif"
  if random(5) = 1 then
    go("birdy")
  end if
end
