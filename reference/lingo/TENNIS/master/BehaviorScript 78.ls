on enterFrame
  global effectspath, ballpos, miss, loser, runcount
  sound playFile 1, effectspath & "raket" & random(3) & ".aif"
  loser = random(6)
  loser = loser - 1
  miss = "yes"
  if member(the memberNum of sprite 7).name contains "shrt" then
    x = the locH of sprite 7 - 25
    y = the locV of sprite 7 - 160
    y2 = 500
    x2 = 130 + random(50)
    x3 = x - ((x - x2) * 2)
    y3 = 313
    x4 = (x - x3) / 15
    y4 = random(10) + 2
  else
    x = the locH of sprite 7 - 25
    y = the locV of sprite 7 - 90
    y2 = random(130)
    y2 = y2 + 20
    x2 = 230 + random(50)
    x3 = x - ((x - x2) * 2)
    y3 = 313
    x4 = (x - x3) / 16
    y4 = random(20) + 30
  end if
  ballpos = x & "," & y & "," & x2 & "," & y2 & "," & x3 & "," & y3 & "," & x4 & "," & y4
  set the locH of sprite 9 to x
  set the locV of sprite 9 to y
  set the memberNum of sprite 9 to the number of member "ball1"
  updateStage()
  puppetSprite(13, 1)
  put "1" into item 2 of runcount
  put "1" into item 3 of runcount
  if member(the memberNum of sprite 7).name contains "hezshrt" then
    if value(item 1 of field "runcount") < 7 then
      set the memberNum of sprite 7 to the number of member ("hezshrt" & value(item 1 of field "runcount")) of castLib 1
      put 1 + value(item 1 of field "runcount") into item 1 of field "runcount"
    else
      set the memberNum of sprite 7 to the number of member "hezstnd" of castLib 1
    end if
  else
    if member(the memberNum of sprite 7).name contains "hezlong" then
      if value(item 1 of field "runcount") < 7 then
        set the memberNum of sprite 7 to the number of member ("hezlong" & value(item 1 of field "runcount")) of castLib 1
        put 1 + value(item 1 of field "runcount") into item 1 of field "runcount"
      else
        set the memberNum of sprite 7 to the number of member "hezstnd" of castLib 1
      end if
    end if
  end if
end
