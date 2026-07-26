on exitFrame
  set the keyDownScript to EMPTY
  set the memberNum of sprite 7 to the number of member "hezstnd"
  puppetSprite(7, 0)
  if random(5) = 1 then
    go("rabbit")
  end if
end
