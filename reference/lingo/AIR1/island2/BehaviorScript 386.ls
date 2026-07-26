on mouseUp
  global monk, soundspath, egozh, egozv, whatodo, nextroomdata
  sound stop 2
  if monk = 1 then
    nextroomdata = "000"
    if (egozv <> 400) and (egozh <> 180) then
      egozv = 400
      egozh = 180
      walkonby()
    else
      if whatodo = "stand" then
        if sprite(9).visible <> 0 then
          sound playFile 1, soundspath & "monk4.aif"
          sprite(9).visible = 0
          play frame "speakmiddle2"
          sprite(9).visible = 1
          sound playFile 1, soundspath & "monk5.aif"
          sprite(30).visible = 0
          play frame "hezmonkreplay"
          sprite(30).visible = 1
          monk = 2
          go("inside")
        else
          monk = 2
        end if
      end if
    end if
  else
    nextroomdata = "000"
    if (egozv <> 400) and (egozh <> 95) then
      egozv = 385
      egozh = 95
      walkonby()
    else
      if whatodo = "stand" then
        if monk = 2 then
          monk = 3
          sprite(30).visible = 0
          sound playFile 1, soundspath & "book1.aif"
          play frame "bookspk"
          sound playFile 1, soundspath & "book2.aif"
          play frame "triviaspk"
          sound playFile 1, soundspath & "book3.aif"
          play frame "bookspk"
          sound playFile 1, soundspath & "book4.aif"
          play frame "triviaspk"
          sound playFile 1, soundspath & "book5.aif"
          play frame "bookspk"
          sound playFile 1, soundspath & "book6.aif"
          play frame "triviaspk"
          sprite(30).visible = 1
          go("insidego")
        else
          sprite(30).visible = 0
          sound playFile 1, soundspath & "playcup.aif"
          play frame "bookspk"
          go("YorN")
        end if
      end if
    end if
  end if
end
