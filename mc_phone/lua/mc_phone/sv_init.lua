-- "addons\\mc_phone\\lua\\mc_phone\\sv_init.lua"
--[[---------------------------------------------------------------------------
McPhone 1.2.0 (N.Y. Noire) - серверная часть звонков. Клиент из скриптхука: cl_init.lua / cl_util.lua / sh_init.lua.
Восстановлено по клиенту (шаг 20), протокол как у сервера:
  McPhone.CallStart       кл -> сер: String номер, Bool служебный, [String служебный номер (911, 5553867)]
                          сер -> кл: String "Connecting"/"Incoming", Entity собеседник, UInt2 тип, [String номер]
                                     тип 0 - обычный, 1 - звонящий с таксофона, 2 - входящий с таксофона,
                                     3 - входящий от службы (номер показывается вместо звонящего)
                          сер -> кл: String "ExtraNumber", String номер - входящий со спецномера (McPhone.IncomingExtra)
  McPhone.CallExtraNumber сер -> кл: String номер, Bool таксофон, Float гудки; кл -> сер: UInt2 (положил трубку)
  McPhone.Accept / CallDeny / CallAccept(Bool) / CallBuisy / CallNotAv(Bool) / End / NoSignal
  McPhone.PhoneStatus     кл -> сер: UInt3 (0 - убран, 1 - в руке, 3 - таксофон), [Bool обновить]
  McPhone.GetUserData     кл -> сер: Bool сон, String тип, String мелодия, String обои, UInt8 r, g, b
  McPhone.Notify          сер -> кл: String заголовок, String текст, Bool звук
  McPhone.Comtact         сер -> кл: String номер, String имя (McPhone.AddContacts(number, name, ply))
  McPhone.ToggleGPS       сер -> кл: String название, Vector точка (McPhone.ToggleGPS(ply, name, pos))
Телефон - предмет инвентаря (McINV.GetPhone), номер - McPhone.NumberChar (персонаж), сигнал - extentions/sv_ep1_noire.lua.
---------------------------------------------------------------------------]]
for _, str in ipairs({
	"McPhone.CallStart", "McPhone.CallDeny", "McPhone.CallAccept", "McPhone.CallExtraNumber", "McPhone.Accept",
	"McPhone.End", "McPhone.Notify", "McPhone.PhoneStatus", "McPhone.GetData", "McPhone.SaveConfig",
	"McPhone.GetUserData", "McPhone.CallBuisy", "McPhone.CallNotAv", "McPhone.PayPhone", "McPhone.Comtact",
	"McPhone.ToggleGPS", "McPhone.SignalChange", "McPhone.NoSignal", "McPhone.SaveTowers", "McPhone.SpawnTower",
	"McPhone.RemoveTowers", "McPhone.SendMail", "McPhone.SendSMS",
}) do
	util.AddNetworkString(str)
end

McPhone.Noire = McPhone.Noire or {}
McPhone.Noire.Config = {
	RingTime = 20, -- сколько секунд звонит входящий без ответа (клиент сам сбрасывает через 15)
	ExtraDelay = 3, -- гудки перед автоответчиком спецномера
	PayPhonePrice = 2, -- цена звонка с таксофона, 0 - бесплатно
	PayPhoneDist = 150, -- отошёл от таксофона дальше - трубка повешена
	CallDelay = 1.5, -- антиспам между звонками
}

local cfg = McPhone.Noire.Config

-- служебные звонки "от имени" спецномера: кто может звонить и кому
McPhone.Noire.ServiceNumbers = {
	["911"] = function(caller, receiver)
		return caller:isCP() or (caller.isEMS and caller:isEMS())
	end,
	["5553867"] = function(caller, receiver)
		return TEAM_CAR and receiver:Team() == TEAM_CAR
	end,
}

--[[---------------------------------------------------------------------------
Общие функции
---------------------------------------------------------------------------]]
function McPhone.Notify(ply, title, text, snd)
	if not IsValid(ply) then return end

	net.Start("McPhone.Notify")
		net.WriteString(title or "")
		net.WriteString(text or "")
		net.WriteBool(snd and true or false)
	net.Send(ply)
end

function McPhone.DefaultNotify(ply, type, len, text)
	if DarkRP and DarkRP.notify then DarkRP.notify(ply, type, len, text) end
end

function McPhone.SetCallStatus(ply, status)
	if not IsValid(ply) or not ply.setDarkRPVar then return end

	ply:setDarkRPVar("McPhone.Active", math.Clamp(math.floor(tonumber(status) or 0), 0, 7))
end

function McPhone.GetSignal(ply)
	if not McPhone.EP1 or not McPhone.EP1.Enabled then return 3 end

	return ply.McPhoneSignal or 3
end

function McPhone.CanTalk(ply, incoming)
	return McPhone.CanUsePhone(ply, IsValid(ply.McPayPhone) and not incoming, incoming)
end

-- метка GPS на телефоне игрока (старая метка снимается)
function McPhone.ToggleGPS(ply, name, pos)
	if not IsValid(ply) or not isvector(pos) then return end

	net.Start("McPhone.ToggleGPS")
		net.WriteString(name or "")
		net.WriteVector(pos)
	net.Send(ply)
end

function McPhone.IsBusy(ply)
	return IsValid(ply.McPhoneOnCall) or IsValid(ply.McPhoneInCall) or IsValid(ply.McPhoneCalling)
		or ply.McPhoneExtra ~= nil or ply.McPhoneExtraIncoming ~= nil
end

-- профиль телефона: что прислал клиент, иначе - из предмета в инвентаре
function McPhone.GetProfile(ply)
	if ply.McPhoneData then return ply.McPhoneData end

	local _, item = McINV and McINV.GetPhone and McINV.GetPhone(ply)

	return item and item.ud or nil
end

local function stopRing(ply)
	if ply.McPhoneSound then
		ply.McPhoneSound:Stop()
		ply.McPhoneSound = nil
	end

	timer.Remove("McPhone.Ring" .. ply:EntIndex())
end

local function startRing(ply)
	stopRing(ply)

	local profile = McPhone.GetProfile(ply)
	local tone = profile and profile.Ringtone

	if ply:IsBot() then tone = "tone_" .. math.random(1, 8) .. ".wav" end
	if not isstring(tone) or tone == "" or string.find(tone, "..", 1, true) then return end
	if not string.find(tone, ".", 1, true) then tone = tone .. ".wav" end

	ply.McPhoneSound = CreateSound(ply, "mc_phone/ring/" .. tone)
	ply.McPhoneSound:SetSoundLevel(70)
	ply.McPhoneSound:Play()
end

local function notAvailable(ply, payphone)
	net.Start("McPhone.CallNotAv")
		net.WriteBool(payphone and true or false)
	net.Send(ply)
end

local function rpLog(ply, target, text)
	if not McPhone.Config.DarkRPLog or not DarkRP or not DarkRP.log then return end

	DarkRP.log("other", ply, target, text)
end

--[[---------------------------------------------------------------------------
Спецномера (автоответчики, 911, дилер, механик...)
---------------------------------------------------------------------------]]
function McPhone.SendExtra(ply, number, payphone, delay)
	net.Start("McPhone.CallExtraNumber")
		net.WriteString(number)
		net.WriteBool(payphone and true or false)
		net.WriteFloat(delay or 0)
	net.Send(ply)
end

function McPhone.CallExtra(caller, number, payphone)
	local tab = McPhone.ExtraNumbers[number]
	if not tab then return end

	if (tab.checkNumber and tab.checkNumber(caller))
		or (tab.delay_func and McPhone.ExtraNumbersFunc[tab.delay_func] and McPhone.ExtraNumbersFunc[tab.delay_func](caller, payphone)) then
		notAvailable(caller, payphone)
		hook.Run("McPhone.Hook.UnsuccessCall", caller, number)
		return
	end

	caller.McPhoneExtra = number

	-- 911: после гудков клиент покажет меню служб (services_request)
	if number == "911" then
		caller.Dispatcher_Phone = CurTime()
		caller.Dispatcher_PayPhone = payphone or nil
	end

	McPhone.SendExtra(caller, number, payphone, cfg.ExtraDelay)
	hook.Run("McPhone.Hook.ExtraNumberCalled", caller, tab, number)

	timer.Create("McPhone.Extra" .. caller:EntIndex(), cfg.ExtraDelay + (tab.delay or 5) + 3, 1, function()
		if IsValid(caller) and caller.McPhoneExtra == number then
			caller.McPhoneExtra = nil
		end
	end)
end

-- входящий звонок со спецномера (квесты, NPC): McPhone.IncomingExtra(ply, "5552222")
function McPhone.IncomingExtra(ply, number)
	if not IsValid(ply) or not McPhone.ExtraNumbers[number] then return false end
	if not McPhone.CanUsePhone(ply, false, true) or McPhone.IsBusy(ply) or McPhone.GetSignal(ply) < 1 then return false end

	ply.McPhoneExtraIncoming = number
	startRing(ply)

	net.Start("McPhone.CallStart")
		net.WriteString("ExtraNumber")
		net.WriteString(number)
	net.Send(ply)

	timer.Create("McPhone.Ring" .. ply:EntIndex(), cfg.RingTime, 1, function()
		if not IsValid(ply) or ply.McPhoneExtraIncoming ~= number then return end

		ply.McPhoneExtraIncoming = nil
		stopRing(ply)
	end)

	return true
end

--[[---------------------------------------------------------------------------
Звонок
---------------------------------------------------------------------------]]
function McPhone.StartCall(caller, number, srvnum)
	local payphone = IsValid(caller.McPayPhone)

	if not McPhone.CanUsePhone(caller, payphone) then return end

	if not payphone and McPhone.GetSignal(caller) < 1 then
		net.Start("McPhone.NoSignal")
		net.Send(caller)
		return
	end

	if payphone and cfg.PayPhonePrice > 0 then
		if not caller:canAfford(cfg.PayPhonePrice) then
			McPhone.CallExtra(caller, "nomoney", true)
			return
		end

		caller:addMoney(-cfg.PayPhonePrice)
	end

	local receiver = McPhone.GetByNumber(number)

	if istable(receiver) then
		McPhone.CallExtra(caller, number, payphone)
		return
	end

	if not IsValid(receiver) or receiver == caller or not McPhone.CanUsePhone(receiver, false, true) or McPhone.GetSignal(receiver) < 1 then
		notAvailable(caller, payphone)
		hook.Run("McPhone.Hook.UnsuccessCall", caller, number)
		return
	end

	if McPhone.IsBusy(receiver) or IsValid(receiver.McPayPhone) then
		net.Start("McPhone.CallBuisy")
		net.Send(caller)
		hook.Run("McPhone.Hook.UnsuccessCall", caller, number)
		return
	end

	if hook.Run("McPhone.Hook.CanCall", caller, receiver) == false then
		notAvailable(caller, payphone)
		return
	end

	local rtype = payphone and 2 or 0
	local check = srvnum and McPhone.Noire.ServiceNumbers[srvnum]

	if check and not payphone and check(caller, receiver) then
		rtype = 3
	else
		srvnum = nil
	end

	receiver.McPhoneInCall = caller
	caller.McPhoneCalling = receiver
	startRing(receiver)

	net.Start("McPhone.CallStart")
		net.WriteString("Connecting")
		net.WriteEntity(receiver)
		net.WriteUInt(payphone and 1 or 0, 2)
	net.Send(caller)

	net.Start("McPhone.CallStart")
		net.WriteString("Incoming")
		net.WriteEntity(caller)
		net.WriteUInt(rtype, 2)
		if rtype == 3 then net.WriteString(srvnum) end
	net.Send(receiver)

	timer.Create("McPhone.Ring" .. receiver:EntIndex(), cfg.RingTime, 1, function()
		if IsValid(receiver) and IsValid(caller) and receiver.McPhoneInCall == caller then
			McPhone.EndCall(receiver)
		end
	end)

	rpLog(caller, receiver, "позвонил" .. (payphone and " с таксофона" or "") .. (srvnum and " (служба " .. srvnum .. ")" or ""))
	hook.Run("McPhone.Hook.CallStart", caller, receiver)
end

-- положить трубку / сбросить / отменить
function McPhone.EndCall(ply)
	if not IsValid(ply) then return end

	stopRing(ply)
	ply.McPhoneExtra = nil
	ply.McPhoneExtraIncoming = nil

	local inc = ply.McPhoneInCall -- мне звонят - сбросил
	if IsValid(inc) and inc.McPhoneCalling == ply then
		inc.McPhoneCalling = nil

		net.Start("McPhone.CallBuisy")
		net.Send(inc)

		hook.Run("McPhone.Hook.OnCallEnd", ply, inc)
	end

	local out = ply.McPhoneCalling -- я звоню - передумал
	if IsValid(out) and out.McPhoneInCall == ply then
		out.McPhoneInCall = nil
		stopRing(out)

		net.Start("McPhone.End")
		net.Send(out)

		hook.Run("McPhone.Hook.OnCallEnd", ply, out)
	end

	local on = ply.McPhoneOnCall -- разговор
	if IsValid(on) and on.McPhoneOnCall == ply then
		on.McPhoneOnCall = nil

		net.Start("McPhone.CallBuisy")
		net.Send(on)

		rpLog(ply, on, "закончил разговор по телефону")
		hook.Run("McPhone.Hook.OnCallEnd", ply, on)
	end

	ply.McPhoneInCall = nil
	ply.McPhoneCalling = nil
	ply.McPhoneOnCall = nil
end

-- повесить трубку таксофона
function McPhone.ReleasePayPhone(ply)
	local ent = ply.McPayPhone
	ply.McPayPhone = nil

	if IsValid(ent) and ent.SetStatIdle then
		ent:SetStatIdle(true)
		ent:EmitSound("mc_phone/payphone_out.wav")
	end
end

--[[---------------------------------------------------------------------------
Сеть
---------------------------------------------------------------------------]]
net.Receive("McPhone.CallStart", function(_, caller)
	local number = string.gsub(string.sub(net.ReadString(), 1, 32), "[%s%-%(%)]", "")
	local srv = net.ReadBool()
	local srvnum = srv and string.sub(net.ReadString(), 1, 32) or nil

	-- клиент механика шлёт звонок каждому механику подряд - дозвон идёт до первого
	if McPhone.IsBusy(caller) then return end
	if (caller.McPhoneCallDelay or 0) > CurTime() then return end
	caller.McPhoneCallDelay = CurTime() + cfg.CallDelay

	if number == "" then return end

	McPhone.StartCall(caller, number, srvnum)
end)

net.Receive("McPhone.CallDeny", function(_, ply)
	McPhone.EndCall(ply)
end)

net.Receive("McPhone.CallExtraNumber", function(_, ply)
	net.ReadUInt(2)
	ply.McPhoneExtra = nil
	timer.Remove("McPhone.Extra" .. ply:EntIndex())
end)

net.Receive("McPhone.Accept", function(_, ply)
	if ply.McPhoneExtraIncoming then
		local number = ply.McPhoneExtraIncoming
		ply.McPhoneExtraIncoming = nil
		stopRing(ply)

		if not McPhone.CanUsePhone(ply, false, true) then return end

		ply.McPhoneExtra = number
		McPhone.SendExtra(ply, number, false, 0)
		hook.Run("McPhone.Hook.ExtraNumberAccepted", ply, number)

		local tab = McPhone.ExtraNumbers[number]
		timer.Create("McPhone.Extra" .. ply:EntIndex(), (tab and tab.delay or 5) + 3, 1, function()
			if IsValid(ply) and ply.McPhoneExtra == number then ply.McPhoneExtra = nil end
		end)

		return
	end

	local caller = ply.McPhoneInCall
	if not IsValid(caller) or caller.McPhoneCalling ~= ply then return end
	if not McPhone.CanUsePhone(ply, false, true) then return end

	stopRing(ply)
	ply.McPhoneInCall = nil
	caller.McPhoneCalling = nil
	ply.McPhoneOnCall = caller
	caller.McPhoneOnCall = ply

	net.Start("McPhone.CallAccept")
		net.WriteBool(IsValid(caller.McPayPhone))
	net.Send(caller)

	net.Start("McPhone.CallAccept")
		net.WriteBool(false)
	net.Send(ply)

	rpLog(ply, caller, "ответил на звонок")
	hook.Run("McPhone.Hook.Accept", ply, caller)
end)

net.Receive("McPhone.PhoneStatus", function(_, ply)
	local status = net.ReadUInt(3)
	local update = net.ReadBool()

	if status > 0 and status ~= 3 and not McPhone.HasPhone(ply) then status = 0 end
	if status == 3 and not IsValid(ply.McPayPhone) then status = 0 end

	if update then
		McPhone.SetCallStatus(ply, 0)

		timer.Create("McPhone.Status" .. ply:EntIndex(), 1, 1, function()
			if IsValid(ply) then McPhone.SetCallStatus(ply, status) end
		end)

		return
	end

	timer.Remove("McPhone.Status" .. ply:EntIndex())
	McPhone.SetCallStatus(ply, status)
end)

-- таксофон: трубку повесили (клиент закрыл меню) - сущность mc_payphone тоже слушает, тут страховка
net.Receive("McPhone.PayPhone", function(_, ply)
	local ent = net.ReadEntity()

	if IsValid(ent) and ent.IsPayPhone and ply.McPayPhone == ent then
		McPhone.ReleasePayPhone(ply)
	elseif not IsValid(ent) and ply.McPayPhone then
		McPhone.ReleasePayPhone(ply)
	end
end)

net.Receive("McPhone.GetUserData", function(_, ply)
	if (ply.McPhoneUDDelay or 0) > CurTime() then return end
	ply.McPhoneUDDelay = CurTime() + 0.3

	local data = {
		Sleep = net.ReadBool(),
		PhoneType = string.sub(net.ReadString(), 1, 32),
		Ringtone = string.sub(net.ReadString(), 1, 64),
		WallPaper = string.sub(net.ReadString(), 1, 96),
	}

	data.PhoneColor = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8))

	ply.McPhoneData = data

	-- спящий режим: входящие не проходят, текущий звонок не рвём
	if McINV and McINV.SavePhoneProfile then
		McINV.SavePhoneProfile(ply, data)
	end
end)

--[[---------------------------------------------------------------------------
Голос: собеседники слышат друг друга (при слабом сигнале - с обрывами)
---------------------------------------------------------------------------]]
local function goodLine(ply1, ply2)
	local s1 = IsValid(ply1.McPayPhone) and 3 or McPhone.GetSignal(ply1)
	local s2 = IsValid(ply2.McPayPhone) and 3 or McPhone.GetSignal(ply2)

	if s1 < 1 or s2 < 1 then return false end
	if s1 > 1 and s2 > 1 then return true end

	return math.random(1, 50) > 20
end

hook.Add("PlayerCanHearPlayersVoice", "McPhone.PlayerCanHearPlayersVoice", function(listener, talker)
	if listener.McPhoneOnCall == talker and talker.McPhoneOnCall == listener and goodLine(listener, talker) then
		return true, false
	end
end)

--[[---------------------------------------------------------------------------
Жизненный цикл
---------------------------------------------------------------------------]]
local function hangUp(ply)
	if not IsValid(ply) then return end

	McPhone.EndCall(ply)

	if ply.McPayPhone then McPhone.ReleasePayPhone(ply) end

	McPhone.SetCallStatus(ply, 0)
end

hook.Add("PlayerDeath", "McPhone.Noire", hangUp)
hook.Add("PlayerSilentDeath", "McPhone.Noire", hangUp)
hook.Add("PlayerDisconnected", "McPhone.Noire", hangUp)
hook.Add("MCR.PreUnloadCharacter", "McPhone.Noire", function(ply)
	hangUp(ply)
	ply.McPhoneData = nil
end)

-- телефон в руке: жив, есть в инвентаре, не связан и не без сознания (спящий режим разговор не рвёт)
local function canHold(ply)
	return ply:Alive() and McPhone.HasPhone(ply) and not ply:getDarkRPVar("unconscious") and not ply:getDarkRPVar("HandCuffed")
end

-- телефон выкинули / связали / вырубили / отошёл от таксофона - звонок рвётся
timer.Create("McPhone.Noire.Check", 1, 0, function()
	for _, ply in ipairs(player.GetHumans()) do
		local pay = ply.McPayPhone

		if pay ~= nil then
			if not IsValid(pay) or not ply:Alive() or ply:GetPos():DistToSqr(pay:GetPos()) > cfg.PayPhoneDist ^ 2 then
				McPhone.EndCall(ply)
				McPhone.ReleasePayPhone(ply)
				McPhone.SetCallStatus(ply, 0)
			end

			continue
		end

		local hold = canHold(ply)

		if (ply:getDarkRPVar("McPhone.Active") or 0) > 0 and not hold then
			McPhone.SetCallStatus(ply, 0)
		end

		if (IsValid(ply.McPhoneOnCall) or IsValid(ply.McPhoneCalling) or IsValid(ply.McPhoneInCall)) and not hold then
			McPhone.EndCall(ply)
		end
	end
end)
