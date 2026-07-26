on exitFrame
  global soundspath, effectspath
  soundspath("tv")
  sound stop 2
  repeat with i = 30 to 36
    sprite(i).visible = 0
  end repeat
  x = random(5)
  if x = 1 then
    sprite(30).visible = 1
    sprite(31).visible = 1
  else
    if x = 2 then
      sprite(32).visible = 1
    else
      if x = 3 then
        sprite(33).visible = 1
      else
        if x = 4 then
          sprite(34).visible = 1
        else
          if x = 5 then
            sprite(35).visible = 1
            sprite(36).visible = 1
          end if
        end if
      end if
    end if
  end if
end
