on exitFrame
  global effectspath
  if not soundBusy(2) then
    x = random(3)
    case x of
      1:
        sound playFile 2, effectspath & "hotel2.aif"
      2:
        sound playFile 2, effectspath & "liber.aif"
      3:
        sound playFile 2, effectspath & "hotelup.aif"
    end case
  end if
  go(the frame)
end
