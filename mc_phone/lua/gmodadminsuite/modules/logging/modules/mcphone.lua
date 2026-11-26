--leak by matveicher
--vk group - https://vk.com/gmodffdev
--steam - https://steamcommunity.com/profiles/76561198968457747/
--ds server - https://discord.gg/V329W7Ce8g
--ds - matveicher#2000

--if (not GAS.Logging.Modules:IsAddonInstalled("McPhone")) then return end
local MODULE = GAS.Logging:MODULE()
MODULE.Category = "McPhone"
MODULE.Name = "Email/SMS"
MODULE.Colour = Color(0, 150, 255)

MODULE:Setup(function()
	MODULE:Hook("McPhone.Hook.SendMail", "blogs.mcphone.email", function(ply, str1, str2)
		MODULE:LogPhrase("{1} sent email ➞ {2}", GAS.Logging:FormatPlayer(ply), GAS.Logging:Highlight(str1 .. " | " .. str2))
	end)

	MODULE:Hook("McPhone.Hook.SendSMS", "blogs.mcphone.sms", function(ply, ply2, str)
		MODULE:LogPhrase("{1} messaged ➞ {2}: {3}", GAS.Logging:FormatPlayer(ply), GAS.Logging:FormatPlayer(ply2), GAS.Logging:Highlight(str))
	end)
end)

GAS.Logging:AddModule(MODULE)

local MODULE = GAS.Logging:MODULE()
MODULE.Category = "McPhone"
MODULE.Name = "Calls"
MODULE.Colour = Color(0, 150, 255)

MODULE:Setup(function()
	MODULE:Hook("McPhone.Hook.CallStart", "blogs.mcphone.callstart", function(ply, ply2)
		MODULE:LogPhrase("{1} started call to ➞ {2}", GAS.Logging:FormatPlayer(ply), GAS.Logging:FormatPlayer(ply2))
	end)

	MODULE:Hook("McPhone.Hook.Accept", "blogs.mcphone.callaccept", function(ply, ply2)
		MODULE:LogPhrase("{1} accepted call from ➞ {2}", GAS.Logging:FormatPlayer(ply), GAS.Logging:FormatPlayer(ply2))
	end)

	MODULE:Hook("McPhone.Hook.UnsuccessCall", "blogs.mcphone.callunseccess", function(ply, numb)
		MODULE:LogPhrase("{1} tried to call ➞ {2}", GAS.Logging:FormatPlayer(ply), GAS.Logging:Highlight(numb))
	end)

	MODULE:Hook("McPhone.Hook.ExtraNumberCalled", "blogs.mcphone.callextranumber", function(ply, numb)
		MODULE:LogPhrase("{1} called ➞ {2}", GAS.Logging:FormatPlayer(ply), GAS.Logging:Highlight(numb.nicename))
	end)

	MODULE:Hook("McPhone.Hook.ExtraNumberCalled", "blogs.mcphone.callextranumber", function(ply, numb)
		MODULE:LogPhrase("{1} called ➞ {2}", GAS.Logging:FormatPlayer(ply), GAS.Logging:Highlight(numb.nicename))
	end)

	MODULE:Hook("McPhone.Hook.OnCallEnd", "blogs.mcphone.callstopped", function(ply)
		MODULE:LogPhrase("{1} stopped phone call", GAS.Logging:FormatPlayer(ply))
	end)
end)

GAS.Logging:AddModule(MODULE)
local MODULE = GAS.Logging:MODULE()
MODULE.Category = "McPhone"
MODULE.Name = "Actions"
MODULE.Colour = Color(0, 150, 255)

MODULE:Setup(function()
	MODULE:Hook("McPhone.Hook.OnPhonePicked", "blogs.mcphone.pickup", function(ply)
		MODULE:LogPhrase("{1} picked phone", GAS.Logging:FormatPlayer(ply))
	end)

	MODULE:Hook("McPhone.Hook.OnPhoneDropped", "blogs.mcphone.drop", function(ply)
		MODULE:LogPhrase("{1} droped phone", GAS.Logging:FormatPlayer(ply))
	end)
end)

GAS.Logging:AddModule(MODULE)
--leak by matveicher
--vk group - https://vk.com/gmodffdev
--steam - https://steamcommunity.com/profiles/76561198968457747/
--ds server - https://discord.gg/V329W7Ce8g
--ds - matveicher#2000
