-- ╔═╗╔═╦═══╦═══╗───────────────────────
-- ║║╚╝║║╔═╗║╔═╗║───────────────────────
-- ║╔╗╔╗║║─║║╚══╗───────────────────────
-- ║║║║║║║─║╠══╗║──By MacTavish <3──────
-- ║║║║║║╚═╝║╚═╝║───────────────────────
-- ╚╝╚╝╚╩══╗╠═══╝───────────────────────
-- ────────╚╝───────────────────────────
--──────────────────────────────────--
---------- Util functions ------------
--──────────────────────────────────--
function MQS.CheckID(id)
	id = string.match( id, "^[a-zA-Z0-9_]*$" )
	if tonumber(id) then return false end
	return id
end

function MQS.TableCompress(data)
	local json_data = util.TableToJSON(data, false)
	local compressed_data = util.Compress(json_data)
	local bytes_number = string.len(compressed_data)

	return compressed_data, bytes_number
end

function MQS.TableDecompress(compressed_data)
	local json_data = util.Decompress(compressed_data) or "[]"
	local data = util.JSONToTable(json_data)

	return data
end

function MQS.HasNPCLink(link, npc)
	if istable(link) then return link.id == npc end

	return link == npc
end

function MQS.QuestStatusCheck(tk, ply)
	if CLIENT and not ply then ply = LocalPlayer() end
	if ply.MQSdata and ply.MQSdata.Stored and ply.MQSdata.Stored.QuestList and ply.MQSdata.Stored.QuestList[tk] then return ply.MQSdata.Stored.QuestList[tk] end
	return false
end

function MQS.CanStartTask(tk, ply, npc, force)
	if CLIENT then
		ply = LocalPlayer()
	end

	local task = MQS.Quests[tk]

	if not task then return false, MSD.GetPhrase("inv_quest") end

	if not ply or not IsValid(ply) or not ply:Alive() then return false, MSD.GetPhrase("dead") end

	if MQS.HasQuest(ply) then return false, MSD.GetPhrase("active_quest") end

	if not force then
		local block, reason = hook.Call("MQS.PreventTaskStart", nil, ply, tk, task)
		if block then return false, reason or MSD.GetPhrase("inactive_quest") end

		if not MQS.IsEditor(ply) and not task.active and not MQS.Config.NPC.enable then return false, MSD.GetPhrase("inactive_quest") end

		if (CLIENT or not MQS.IsEditor(ply)) and MQS.Config.NPC.enable and (not npc or not task.link or not MQS.HasNPCLink(task.link, npc)) then return false, MSD.GetPhrase("inactive_quest") end

		local tm = ply:Team()

		if not task.team_blacklist and task.team_whitelist and not task.team_whitelist[tm] then return false, MSD.GetPhrase("team_bl") end

		if task.team_blacklist and task.team_whitelist and task.team_whitelist[tm] then return false, MSD.GetPhrase("team_bl") end

		if task.need_players and #player.GetAll() < task.need_players then return false, MSD.GetPhrase("no_players") end

		if task.cant_replay and ply.MQSdata.Stored and ply.MQSdata.Stored.QuestList and ply.MQSdata.Stored.QuestList[tk] then return false, MSD.GetPhrase("q_noreplay") end

		if task.quest_needed and MQS.Quests[task.quest_needed] and not MQS.Quests[task.quest_needed].looped and (not ply.MQSdata.Stored.QuestList or not ply.MQSdata.Stored.QuestList[task.quest_needed]) then return false, MSD.GetPhrase("q_needquest") end

		if not task.cooldow_perply and MQS.TaskQueue[tk] and MQS.TaskQueue[tk] > CurTime() then return false, MSD.GetPhrase("q_time_wait") end

		if task.cooldow_perply and ply.MQSdata.Stored.CoolDown and ply.MQSdata.Stored.CoolDown[tk] and ply.MQSdata.Stored.CoolDown[tk] > os.time() then return false, MSD.GetPhrase("q_time_wait") end

		if task.limit and MQS.TaskCount[tk] and MQS.TaskCount[tk] >= task.limit then return false, MSD.GetPhrase("q_play_limit") end

		if task.conflictlist then
			for qst, _ in pairs(task.conflictlist) do
				if MQS.TaskCount[qst] and MQS.TaskCount[qst] > 0 then
					return false, MSD.GetPhrase("q_play_limit")
				end
			end
		end

		if task.quest_blacklist and ply.MQSdata.Stored.QuestList then
			for qst, _ in pairs(task.quest_blacklist) do
				if ply.MQSdata.Stored.QuestList[qst] then
					return false, MSD.GetPhrase("inactive_quest")
				end
			end
		end

		if task.need_teamplayers then
			for tms, num in pairs(task.need_teamplayers) do
				if team.NumPlayers(tms) < tonumber(num) then return false, MSD.GetPhrase("no_players_team") end
			end
		end
	end

	return true
end

function MQS.ActiveQuestLists(npc, ply)
	if CLIENT and not ply then ply = LocalPlayer() end

	local a_quests = {}

	for k, v in pairs(MQS.Quests) do
		if MQS.CanStartTask(k, ply, npc) then
			a_quests[k] = true
		end
	end

	return a_quests
end

-- шаг 31: из скриптхука сервера N.Y. Noire (mc_quests/lua/mqs/core/sh_util.lua) -
-- выполненные задания и «Истории» в F4 -> «Особые услуги» (msd_ui/msdf4menu.lua; награды выдаёт glac/sv_creditsys.lua).
-- Сами задания season1_* создаются в редакторе квестов MQS на сервере, в скриптхуке их нет.
function MQS.QuestFinished(quest, ply)
	if CLIENT and not ply then
		ply = LocalPlayer()
	end

	if not IsValid(ply) then return false end

	if ply.MQSdata and ply.MQSdata.Stored and ply.MQSdata.Stored.QuestList and ply.MQSdata.Stored.QuestList[quest] then return true end

	return false
end

MQS.Episodes = {}
MQS.Episodes[1] = {}

MQS.Episodes[1].Episodes = {
	[1] = "season1_civilian_1",
	[2] = "season1_civilian_2",
	[3] = "season1_civilian_3",
	[4] = "season1_civilian_4",
	[5] = "season1_civilian_5",
	[6] = "season1_govern_1",
	[7] = "season1_govern_2",
	[8] = "season1_govern_3",
	[9] = "season1_govern_4",
	[10] = "season1_govern_5",
	[11] = "season1_criminal_1",
	[12] = "season1_criminal_2",
	[13] = "season1_criminal_3",
	[14] = "season1_criminal_4",
	[15] = "season1_criminal_5",
}

MQS.Episodes[1].EpisodesSorted = {
	[1] = {
		[1] = "season1_civilian_1",
		[2] = "season1_civilian_2",
		[3] = "season1_civilian_3",
		[4] = "season1_civilian_4",
		[5] = "season1_civilian_5",
	},
	[2] = {
		[1] = "season1_govern_1",
		[2] = "season1_govern_2",
		[3] = "season1_govern_3",
		[4] = "season1_govern_4",
		[5] = "season1_govern_5",
	},
	[3] = {
		[1] = "season1_criminal_1",
		[2] = "season1_criminal_2",
		[3] = "season1_criminal_3",
		[4] = "season1_criminal_4",
		[5] = "season1_criminal_5",
	}
}

MQS.Episodes[1].Rewards = {
	{
		name = "2500$",
		icon = Material("gmodla/f4/stuff/onemoney.png", "smooth"),
		premium = false,
		dec = "Денежное вознаграждение за очки прогресса",
		cost = 150,
		give_func = function(ply)
			ply:addMoney(2500)
		end,
	},
	{
		name = "Труба x2",
		icon = Material("gmodla/icons/pipe.png", "smooth"),
		dec = "Предмет можно использовать для ближнего боя; после разблокировки он автоматически попадёт в ваше хранилище",
		premium = true,
		cost = 300,
		give_func = function(ply)
			local item = {
				class = "mlw_pipe",
				model = "models/weapons/tfa_nmrih/w_me_pipe_lead.mdl",
				dt = {
					eclass = "mlw_pipe"
				},
			}

			ply:AddBankItem(INV_WEAPON, item)
			ply:AddBankItem(INV_WEAPON, item)
		end,
	},
	{
		name = "Beretta M9",
		icon = Material("gmodla/icons/m9.png", "smooth"),
		dec = "Пистолет; после разблокировки он автоматически попадёт в ваше хранилище",
		premium = false,
		cost = 200,
		give_func = function(ply)
			local item = {
				class = "mwb_m9",
				name = "Beretta M9",
				gunstate = 1,
				weight = 1.02,
				model = "models/viper/mw/weapons/w_m9.mdl",
				dt = {
					eclass = "mwb_m9"
				},
				att_saved = {
					{
						["Slot"] = 1,
						["m_Index"] = "att_ammo",
					},
					{
						["Slot"] = 2,
						["m_Index"] = "attachment_vm_pi_mike9_receiver_v2",
					},
					{
						["Slot"] = 3,
						["m_Index"] = "attachment_vm_pi_mike9_pstlgrpcust",
					},
					{
						["Slot"] = 4,
						["m_Index"] = "attachment_vm_pi_mike9_barauto",
					},
					{
						["Slot"] = 5,
						["m_Index"] = "att_muzzle",
					}
				},
			}

			ply:AddBankItem(INV_WEAPON, item)
		end,
	},
	{
		name = "2500$",
		icon = Material("gmodla/f4/stuff/onemoney.png", "smooth"),
		dec = "Денежное вознаграждение за очки прогресса",
		premium = false,
		cost = 150,
		give_func = function(ply)
			ply:addMoney(2500)
		end,
	},
	{
		name = "Лёгкий бронежилет x2",
		icon = Material("gmodla/icons/armor2.png", "smooth"),
		dec = "Лёгкий бронежилет; после разблокировки он автоматически попадёт в ваше хранилище",
		premium = false,
		cost = 300,
		give_func = function(ply)
			local item = {
				class = "armor",
				name = "Лёгкий бронежилет",
				model = "models/tnb/items/wintercoat.mdl",
				material = "gbskins/armor2",
				weight = 2.5,
				dt = {
					eclass = "armor"
				},
			}

			ply:AddBankItem(INV_JUNK, item)
			ply:AddBankItem(INV_JUNK, item)
		end,
	},
	{
		name = "Сигара",
		icon = Material("gmodla/icons/sigar.png", "smooth"),
		dec = "Предмет можно единоразово использовать; после разблокировки он автоматически попадёт в ваше хранилище",
		premium = false,
		cost = 200,
		give_func = function(ply)
			local item = {
				class = "sigar",
				name = "Сигара",
				model = "models/env/decor/ashtray/sigar02.mdl",
				dt = {
					eclass = "sigar"
				},
			}

			ply:AddBankItem(INV_JUNK, item)
		end,
	},
	{
		name = "2500$",
		icon = Material("gmodla/f4/stuff/onemoney.png", "smooth"),
		dec = "Денежное вознаграждение за очки прогресса",
		premium = false,
		cost = 150,
		give_func = function(ply)
			ply:addMoney(2500)
		end,
	},
	{
		name = "Молоток x2",
		icon = Material("gmodla/icons/hammer.png", "smooth"),
		dec = "Предмет можно использовать для ближнего боя; после разблокировки он автоматически попадёт в ваше хранилище",
		premium = true,
		cost = 500,
		give_func = function(ply)
			local item = {
				class = "mlw_hammer",
				model = "models/weapons/tfa_nmrih/w_tool_barricade.mdl",
				dt = {
					eclass = "mlw_hammer"
				},
			}

			ply:AddBankItem(INV_WEAPON, item)
			ply:AddBankItem(INV_WEAPON, item)
		end,
	},
	{
		name = "Beretta 93R",
		icon = Material("gmodla/icons/93r.png", "smooth"),
		dec = "Автоматический пистолет; после разблокировки он автоматически попадёт в ваше хранилище",
		premium = false,
		cost = 300,
		give_func = function(ply)
			local item = {
				class = "mwb_93r",
				name = "Beretta 93R",
				gunstate = 1,
				weight = 1.05,
				model = "models/viper/mw/weapons/w_m9.mdl",
				dt = {
					eclass = "mwb_93r"
				},
				att_saved = {
					{
						["Slot"] = 1,
						["m_Index"] = "att_ammo",
					},
					{
						["Slot"] = 2,
						["m_Index"] = "attachment_vm_pi_mike9_receiver_diamatti",
					},
					{
						["Slot"] = 3,
						["m_Index"] = "attachment_vm_pi_mike9_pstlgrpcust_diamatti",
					},
					{
						["Slot"] = 4,
						["m_Index"] = "attachment_vm_pi_mike9_barauto_diamatti",
					},
					{
						["Slot"] = 5,
						["m_Index"] = "att_muzzle",
					},
				},
			}

			ply:AddBankItem(INV_WEAPON, item)
		end,
	},
	{
		name = "Каска x2",
		icon = Material("gmodla/icons/worker_helmet.png", "smooth"),
		dec = "Предмет можно надеть; после разблокировки он автоматически попадёт в ваше хранилище. Этот предмет пропадет при смерти персонажа или выходе с сервера, если вы его не сняли!",
		premium = false,
		cost = 300,
		give_func = function(ply)
			local item = {
				class = "hardhat",
				name = "Каска",
				model = "models/items/worker_helmet.mdl",
				weight = 1,
				dt = {
					eclass = "hardhat"
				},
			}

			ply:AddBankItem(INV_JUNK, item)
			ply:AddBankItem(INV_JUNK, item)
		end,
	},
	{
		name = "5000$",
		icon = Material("gmodla/f4/stuff/money_p.png", "smooth"),
		dec = "Денежное вознаграждение за очки прогресса",
		premium = false,
		cost = 300,
		give_func = function(ply)
			ply:addMoney(5000)
		end,
	},
	{
		name = "Сигара x3",
		icon = Material("gmodla/icons/sigar.png", "smooth"),
		dec = "Предмет можно единоразово использовать; после разблокировки автоматически попадёт в ваше хранилище",
		premium = true,
		cost = 200,
		give_func = function(ply)
			local item = {
				class = "sigar",
				name = "Сигара",
				model = "models/env/decor/ashtray/sigar02.mdl",
				dt = {
					eclass = "sigar"
				},
			}

			ply:AddBankItem(INV_JUNK, item)
			ply:AddBankItem(INV_JUNK, item)
			ply:AddBankItem(INV_JUNK, item)
		end,
	},
	{
		name = "AUG A1",
		icon = Material("gmodla/icons/aug.png", "smooth"),
		dec = "Редкая автоматическая винтовка; после разблокировки она автоматически попадёт в ваше хранилище",
		premium = true,
		cost = 300,
		give_func = function(ply)
			local item = {
				class = "mwb_aug",
				name = "AUG A1",
				gunstate = 1,
				weight = 3.6,
				model = "models/easy/cw/weapons/w_sm_t9powerburst.mdl",
				dt = {
					eclass = "mwb_aug"
				},
				att_saved = {
					{
						["Slot"] = 1,
						["m_Index"] = "att_ammo",
					},
					{
						["Slot"] = 2,
						["m_Index"] = "att_grip",
					},
					{
						["Slot"] = 3,
						["m_Index"] = "attachment_vm_sm_augolf_arbarrel",
					},
					{
						["Slot"] = 4,
						["m_Index"] = "att_muzzle",
					},
					{
						["Slot"] = 5,
						["m_Index"] = "attachment_vm_sm_augolf_lmgrail",
					}
				},
			}

			ply:AddBankItem(INV_WEAPON, item)
		end,
	},
	{
		name = "10000$",
		icon = Material("gmodla/f4/stuff/fourmoney.png", "smooth"),
		dec = "Денежное вознаграждение за очки прогресса",
		premium = true,
		cost = 500,
		give_func = function(ply)
			ply:addMoney(10000)
		end,
	},
	{
		name = "Мачете x2",
		icon = Material("gmodla/icons/machete.png", "smooth"),
		dec = "Предмет можно использовать для ближнего боя; после разблокировки он автоматически попадёт в ваше хранилище",
		premium = true,
		cost = 500,
		give_func = function(ply)
			local item = {
				class = "mlw_machete",
				model = "models/weapons/tfa_nmrih/w_me_machete.mdl",
				dt = {
					eclass = "mlw_machete"
				},
			}

			ply:AddBankItem(INV_WEAPON, item)
			ply:AddBankItem(INV_WEAPON, item)
		end,
	},
	{
		name = "Авиаторы",
		dec = "Предмет можно надеть; этот предмет всегда доступен для использования во вкладке внешний вид меню F4",
		icon = Material("gmodla/icons/glasses01.png", "smooth"),
		premium = true,
		cost = 5000,
		give_func = function(ply)
			MQS.SetNWStoredData(ply, "episode_1_glasses01", true)
		end,
	},
	{
		name = "2500$",
		icon = Material("gmodla/f4/stuff/onemoney.png", "smooth"),
		premium = true,
		oncomplete = true,
		dec = "Денежное вознаграждение за очки прогресса",
		cost = 250,
		give_func = function(ply)
			ply:addMoney(2500)
		end,
	},
}
