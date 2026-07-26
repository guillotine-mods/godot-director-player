on cursorfunk
  global globalday
  if (the movieName contains "hotel") or (the movieName = "day1.dxr") or (the movieName contains "sea") or (the movieName contains "night1") or (the movieName contains "air") then
    puppetSprite(93, 1)
    if the movieName contains "night" then
      set the memberNum of sprite 93 to the number of member ("night" & globalday) of castLib "master"
      tlkpath("s_night" & globalday)
      soundspath("nights")
    else
      set the memberNum of sprite 93 to the number of member ("day" & globalday) of castLib "master"
      tlkpath("s_day" & globalday)
      if the movieName contains "sea" then
        soundspath("sea")
      else
        if the movieName contains "air" then
          soundspath("air")
        else
          soundspath("days")
        end if
      end if
    end if
    set the volume of sound 2 to 130
    set the cursor of sprite 2 to [member("wlkcur1").memberNum, member("wlkcur2").memberNum]
    set the cursor of sprite 7 to [member("magni1").memberNum, member("magni2").memberNum]
    set the cursor of sprite 8 to [member("magni1").memberNum, member("magni2").memberNum]
    set the cursor of sprite 9 to [member("magni1").memberNum, member("magni2").memberNum]
    set the cursor of sprite 10 to [member("leftcur1").memberNum, member("leftcur2").memberNum]
    set the cursor of sprite 11 to [member("rightcur1").memberNum, member("rightcur2").memberNum]
    set the cursor of sprite 12 to [member("downcur1").memberNum, member("downcur2").memberNum]
    set the cursor of sprite 13 to [member("upcur1").memberNum, member("upcur2").memberNum]
    set the cursor of sprite 14 to [member("trgcur1").memberNum, member("trgcur2").memberNum]
  end if
end
