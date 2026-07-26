on exitFrame
  global newsyz, egozh, egozv, whichsnd
  puppetSprite(9, 0)
  sprite(9).visible = 1
  newsyz = 9
  egozv = 392
  egozh = 250
  whichsnd = "cats"
  go("fort")
  sprite(30).visible = 1
end
