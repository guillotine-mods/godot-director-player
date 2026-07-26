on exitFrame
  global SaveNames
  i = 1
  repeat while i <= 8
    put field("gamename" & i) into item i of SaveNames
    i = 1 + i
  end repeat
  go(1, "macintosh hd:demomac2:navigate.dir")
end
