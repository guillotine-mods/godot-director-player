on exitFrame
  global effectspath, ballpos, miss, runcount
  sound playFile 1, effectspath & "raket" & random(3) & ".aif"
  miss = "yes"
  puppetSprite(9, 1)
  x = the locH of sprite 7 - 25
  y = 98
  y2 = random(130)
  y2 = y2 + 20
  x2 = 230 + random(50)
  x3 = x - ((x - x2) * 2)
  y3 = 313
  x4 = (x - x3) / 11
  y4 = random(20) + 20
  ballpos = x & "," & y & "," & x2 & "," & y2 & "," & x3 & "," & y3 & "," & x4 & "," & y4
  set the locH of sprite 9 to x
  set the locV of sprite 9 to y
  set the memberNum of sprite 9 to the number of member "ball1"
  updateStage()
  puppetSprite(13, 1)
  put "1" into item 2 of runcount
  put "1" into item 3 of runcount
  go(marker("hezanswer") + 1)
  set the keyDownScript to "hitback"
  puppetSprite(7, 1)
end
