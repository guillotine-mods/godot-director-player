on enterFrame
  global globalday
  repeat with i = 10 to 62
    sprite(i).visible = 1
  end repeat
  set the cursor of sprite 9 to [member("lef1").memberNum, member("lef2").memberNum]
  set the cursor of sprite 10 to [member("rit1").memberNum, member("rit2").memberNum]
  set the cursor of sprite 11 to [member("tar1").memberNum, member("tar2").memberNum]
  puppetSprite(11, 1)
  if globalday = 1 then
    set the memberNum of sprite 11 to member("igky", 1).memberNum
  else
    if globalday = 2 then
      set the memberNum of sprite 11 to member("fuel", 1).memberNum
    else
      set the memberNum of sprite 11 to member("sprn", 1).memberNum
    end if
  end if
end
