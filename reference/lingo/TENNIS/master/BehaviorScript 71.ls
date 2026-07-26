on exitFrame
  global serve, miss, runcount, effectspath
  serve = 1
  miss = "yes"
  puppetSprite(9, 0)
  put "0" into field "hatscore"
  put "0" into field "hezscore"
  runcount = "1,1,1"
  sprite(13).visible = 1
  soundspath("games")
end
