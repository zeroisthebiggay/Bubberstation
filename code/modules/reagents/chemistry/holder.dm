//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

var/const/TOUCH = 1 //splashing
var/const/INGEST = 2 //ingestion
var/const/VAPOR = 3 //foam, spray, blob attack
var/const/PATCH = 4 //patches
var/const/INJECT = 5 //injection

///////////////////////////////////////////////////////////////////////////////////

/datum/reagents
	var/list/datum/reagent/reagent_list = new/list()
	var/total_volume = 0
	var/maximum_volume = 100
	var/atom/my_atom = null
	var/chem_temp = 150
	var/last_tick = 1
	var/addiction_tick = 1
	var/list/datum/reagent/addiction_list = new/list()
	var/flags

/datum/reagents/New(maximum=100)
	maximum_volume = maximum

	if(!(flags & REAGENT_NOREACT))
		START_PROCESSING(SSobj, src)

	//I dislike having these here but map-objects are initialised before world/New() is called. >_>
	if(!chemical_reagents_list)
		//Chemical Reagents - Initialises all /datum/reagent into a list indexed by reagent id
		var/paths = subtypesof(/datum/reagent)
		chemical_reagents_list = list()
		for(var/path in paths)
			var/datum/reagent/D = new path()
			chemical_reagents_list[D.id] = D
	if(!chemical_reactions_list)
		//Chemical Reactions - Initialises all /datum/chemical_reaction into a list
		// It is filtered into multiple lists within a list.
		// For example:
		// chemical_reaction_list["plasma"] is a list of all reactions relating to plasma

		var/paths = subtypesof(/datum/chemical_reaction)
		chemical_reactions_list = list()

		for(var/path in paths)

			var/datum/chemical_reaction/D = new path()
			var/list/reaction_ids = list()

			if(D.required_reagents && D.required_reagents.len)
				for(var/reaction in D.required_reagents)
					reaction_ids += reaction

			// Create filters based on each reagent id in the required reagents list
			for(var/id in reaction_ids)
				if(!chemical_reactions_list[id])
					chemical_reactions_list[id] = list()
				chemical_reactions_list[id] += D
				break // Don't bother adding ourselves to other reagent ids, it is redundant.

/datum/reagents/Destroy()
	. = ..()
	STOP_PROCESSING(SSobj, src)
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		qdel(R)
	reagent_list.Cut()
	reagent_list = null
	if(my_atom && my_atom.reagents == src)
		my_atom.reagents = null

/datum/reagents/proc/remove_any(amount = 1)
	var/total_transfered = 0
	var/current_list_element = 1

	current_list_element = rand(1, reagent_list.len)

	while(total_transfered != amount)
		if(total_transfered >= amount)
			break
		if(total_volume <= 0 || !reagent_list.len)
			break

		if(current_list_element > reagent_list.len)
			current_list_element = 1

		var/datum/reagent/R = reagent_list[current_list_element]
		remove_reagent(R.id, 1)

		current_list_element++
		total_transfered++
		update_total()

	handle_reactions()
	return total_transfered

/datum/reagents/proc/remove_all(amount = 1)
	if(total_volume > 0)
		var/part = amount / total_volume
		for(var/reagent in reagent_list)
			var/datum/reagent/R = reagent
			remove_reagent(R.id, R.volume * part)

		update_total()
		handle_reactions()
		return amount

/datum/reagents/proc/get_master_reagent_name()
	var/name
	var/max_volume = 0
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		if(R.volume > max_volume)
			max_volume = R.volume
			name = R.name

	return name

/datum/reagents/proc/get_master_reagent_id()
	var/id
	var/max_volume = 0
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		if(R.volume > max_volume)
			max_volume = R.volume
			id = R.id

	return id

/datum/reagents/proc/trans_to(obj/target, amount=1, multiplier=1, preserve_data=1, no_react = 0)//if preserve_data=0, the reagents data will be lost. Usefull if you use data for some strange stuff and don't want it to be transferred.
	if(!target || !total_volume)
		return
	var/datum/reagents/R
	if(istype(target, /datum/reagents))
		R = target
	else
		if(!target.reagents || src.total_volume<=0)
			return
		R = target.reagents
	amount = min(min(amount, src.total_volume), R.maximum_volume-R.total_volume)
	var/part = amount / src.total_volume
	var/trans_data = null
	for(var/reagent in reagent_list)
		var/datum/reagent/T = reagent
		var/transfer_amount = T.volume * part
		if(preserve_data)
			trans_data = copy_data(T)
		R.add_reagent(T.id, transfer_amount * multiplier, trans_data, chem_temp, no_react = 1) //we only handle reaction after every reagent has been transfered.
		remove_reagent(T.id, transfer_amount)

	update_total()
	R.update_total()
	if(!no_react)
		R.handle_reactions()
		src.handle_reactions()
	return amount

/datum/reagents/proc/copy_to(obj/target, amount=1, multiplier=1, preserve_data=1)
	if(!target)
		return
	if(!target.reagents || src.total_volume<=0)
		return
	var/datum/reagents/R = target.reagents
	amount = min(min(amount, total_volume), R.maximum_volume-R.total_volume)
	var/part = amount / total_volume
	var/trans_data = null
	for(var/reagent in reagent_list)
		var/datum/reagent/T = reagent
		var/copy_amount = T.volume * part
		if(preserve_data)
			trans_data = T.data
		R.add_reagent(T.id, copy_amount * multiplier, trans_data)

	src.update_total()
	R.update_total()
	R.handle_reactions()
	src.handle_reactions()
	return amount

/datum/reagents/proc/trans_id_to(obj/target, reagent, amount=1, preserve_data=1)//Not sure why this proc didn't exist before. It does now! /N
	if (!target)
		return
	if (!target.reagents || src.total_volume<=0 || !src.get_reagent_amount(reagent))
		return

	var/datum/reagents/R = target.reagents
	if(src.get_reagent_amount(reagent)<amount)
		amount = src.get_reagent_amount(reagent)
	amount = min(amount, R.maximum_volume-R.total_volume)
	var/trans_data = null
	for (var/datum/reagent/current_reagent in src.reagent_list)
		if(current_reagent.id == reagent)
			if(preserve_data)
				trans_data = current_reagent.data
			R.add_reagent(current_reagent.id, amount, trans_data, src.chem_temp)
			src.remove_reagent(current_reagent.id, amount, 1)
			break

	src.update_total()
	R.update_total()
	R.handle_reactions()
	//src.handle_reactions() Don't need to handle reactions on the source since you're (presumably isolating and) transferring a specific reagent.
	return amount

/*
				if (!target) return
				var/total_transfered = 0
				var/current_list_element = 1
				var/datum/reagents/R = target.reagents
				var/trans_data = null
				//if(R.total_volume + amount > R.maximum_volume) return 0

				current_list_element = rand(1,reagent_list.len) //Eh, bandaid fix.

				while(total_transfered != amount)
					if(total_transfered >= amount) break //Better safe than sorry.
					if(total_volume <= 0 || !reagent_list.len) break
					if(R.total_volume >= R.maximum_volume) break

					if(current_list_element > reagent_list.len) current_list_element = 1
					var/datum/reagent/current_reagent = reagent_list[current_list_element]
					if(preserve_data)
						trans_data = current_reagent.data
					R.add_reagent(current_reagent.id, (1 * multiplier), trans_data)
					src.remove_reagent(current_reagent.id, 1)

					current_list_element++
					total_transfered++
					src.update_total()
					R.update_total()
				R.handle_reactions()
				handle_reactions()

				return total_transfered
*/

/datum/reagents/proc/metabolize(mob/living/carbon/C, can_overdose = 0)
	if(C)
		chem_temp = C.bodytemperature
		handle_reactions()
	var/need_mob_update = 0
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		if(!R.holder)
			continue
		if(!C)
			C = R.holder.my_atom
		if(C && R)
			if(C.reagent_check(R) != 1)
				if(can_overdose)
					if(R.overdose_threshold)
						if(R.volume >= R.overdose_threshold && !R.overdosed)
							R.overdosed = 1
							need_mob_update += R.overdose_start(C)
					if(R.addiction_threshold)
						if(R.volume >= R.addiction_threshold && !is_type_in_list(R, addiction_list))
							var/datum/reagent/new_reagent = new R.type()
							addiction_list.Add(new_reagent)
					if(R.overdosed)
						need_mob_update += R.overdose_process(C)
					if(is_type_in_list(R,addiction_list))
						for(var/addiction in addiction_list)
							var/datum/reagent/A = addiction
							if(istype(R, A))
								A.addiction_stage = -15 // you're satisfied for a good while.
				need_mob_update += R.on_mob_life(C)

	if(can_overdose)
		if(addiction_tick == 6)
			addiction_tick = 1
			for(var/addiction in addiction_list)
				var/datum/reagent/R = addiction
				if(C && R)
					R.addiction_stage++
					switch(R.addiction_stage)
						if(1 to 10)
							need_mob_update += R.addiction_act_stage1(C)
						if(10 to 20)
							need_mob_update += R.addiction_act_stage2(C)
						if(20 to 30)
							need_mob_update += R.addiction_act_stage3(C)
						if(30 to 40)
							need_mob_update += R.addiction_act_stage4(C)
						if(40 to INFINITY)
							C << "<span class='notice'>You feel like you've gotten over your need for [R.name].</span>"
							addiction_list.Remove(R)
		addiction_tick++
	if(C && need_mob_update) //some of the metabolized reagents had effects on the mob that requires some updates.
		C.updatehealth()
		C.update_canmove()
		C.update_stamina()
	update_total()

/datum/reagents/process()
	if(flags & REAGENT_NOREACT)
		STOP_PROCESSING(SSobj, src)
		return

	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		R.on_tick()

/datum/reagents/proc/set_reacting(react = TRUE)
	if(react)
		// Order is important, process() can remove from processing if
		// the flag is present
		flags &= ~(REAGENT_NOREACT)
		START_PROCESSING(SSobj, src)
	else
		STOP_PROCESSING(SSobj, src)
		flags |= REAGENT_NOREACT

/datum/reagents/proc/conditional_update_move(atom/A, Running = 0)
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		R.on_move (A, Running)
	update_total()

/datum/reagents/proc/conditional_update(atom/A)
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		R.on_update (A)
	update_total()

/datum/reagents/proc/handle_reactions()
	if(flags & REAGENT_NOREACT)
		return //Yup, no reactions here. No siree.

	var/reaction_occured = 0
	do
		reaction_occured = 0
		for(var/reagent in reagent_list)
			var/datum/reagent/R = reagent
			for(var/reaction in chemical_reactions_list[R.id]) // Was a big list but now it should be smaller since we filtered it with our reagent id
				if(!reaction)
					continue

				var/datum/chemical_reaction/C = reaction
				var/total_required_reagents = C.required_reagents.len
				var/total_matching_reagents = 0
				var/total_required_catalysts = C.required_catalysts.len
				var/total_matching_catalysts= 0
				var/matching_container = 0
				var/matching_other = 0
				var/list/multipliers = new/list()
				var/required_temp = C.required_temp

				for(var/B in C.required_reagents)
					if(!has_reagent(B, C.required_reagents[B]))
						break
					total_matching_reagents++
					multipliers += round(get_reagent_amount(B) / C.required_reagents[B])
				for(var/B in C.required_catalysts)
					if(!has_reagent(B, C.required_catalysts[B]))
						break
					total_matching_catalysts++

				if(!C.required_container)
					matching_container = 1

				else
					if(my_atom.type == C.required_container)
						matching_container = 1
				if (isliving(my_atom)) //Makes it so certain chemical reactions don't occur in mobs
					if (C.mob_react)
						return
				if(!C.required_other)
					matching_other = 1

				else if(istype(my_atom, /obj/item/slime_extract))
					var/obj/item/slime_extract/M = my_atom

					if(M.Uses > 0) // added a limit to slime cores -- Muskets requested this
						matching_other = 1

				if(required_temp == 0)
					required_temp = chem_temp


				if(total_matching_reagents == total_required_reagents && total_matching_catalysts == total_required_catalysts && matching_container && matching_other && chem_temp >= required_temp)
					var/multiplier = min(multipliers)
					for(var/B in C.required_reagents)
						remove_reagent(B, (multiplier * C.required_reagents[B]), safety = 1)

					for(var/P in C.results)
						feedback_add_details("chemical_reaction", "[P]|[C.results[P]*multiplier]")
						multiplier = max(multiplier, 1) //this shouldnt happen ...
						add_reagent(P, C.results[P]*multiplier, null, chem_temp)

					var/list/seen = viewers(4, get_turf(my_atom))

					if(!istype(my_atom, /mob)) // No bubbling mobs
						if(C.mix_sound)
							playsound(get_turf(my_atom), C.mix_sound, 80, 1)
						for(var/mob/M in seen)
							M << "<span class='notice'>\icon[my_atom] [C.mix_message]</span>"

					if(istype(my_atom, /obj/item/slime_extract))
						var/obj/item/slime_extract/ME2 = my_atom
						ME2.Uses--
						if(ME2.Uses <= 0) // give the notification that the slime core is dead
							for(var/mob/M in seen)
								M << "<span class='notice'>\icon[my_atom] \The [my_atom]'s power is consumed in the reaction.</span>"
								ME2.name = "used slime extract"
								ME2.desc = "This extract has been used up."

					C.on_reaction(src, multiplier)
					reaction_occured = 1
					break

	while(reaction_occured)
	update_total()
	return 0

/datum/reagents/proc/isolate_reagent(reagent)
	for(var/_reagent in reagent_list)
		var/datum/reagent/R = _reagent
		if(R.id != reagent)
			del_reagent(R.id)
			update_total()

/datum/reagents/proc/del_reagent(reagent)
	for(var/_reagent in reagent_list)
		var/datum/reagent/R = _reagent
		if(R.id == reagent)
			if(istype(my_atom, /mob/living))
				var/mob/living/M = my_atom
				R.on_mob_delete(M)
			qdel(R)
			reagent_list -= R
			update_total()
			my_atom.on_reagent_change()
			check_ignoreslow(my_atom)
			check_gofast(my_atom)
			check_goreallyfast(my_atom)
	return 1

/datum/reagents/proc/check_ignoreslow(mob/M)
	if(istype(M, /mob))
		if(M.reagents.has_reagent("morphine")||M.reagents.has_reagent("ephedrine"))
			return 1
		else
			M.status_flags &= ~IGNORESLOWDOWN

/datum/reagents/proc/check_gofast(mob/M)
	if(istype(M, /mob))
		if(M.reagents.has_reagent("unholywater")||M.reagents.has_reagent("nuka_cola")||M.reagents.has_reagent("stimulants"))
			return 1
		else
			M.status_flags &= ~GOTTAGOFAST

/datum/reagents/proc/check_goreallyfast(mob/M)
	if(istype(M, /mob))
		if(M.reagents.has_reagent("methamphetamine"))
			return 1
		else
			M.status_flags &= ~GOTTAGOREALLYFAST

/datum/reagents/proc/update_total()
	total_volume = 0
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		if(R.volume < 0.1)
			del_reagent(R.id)
		else
			total_volume += R.volume

	return 0

/datum/reagents/proc/clear_reagents()
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		del_reagent(R.id)
	return 0

/datum/reagents/proc/reaction(atom/A, method = TOUCH, volume_modifier = 1, show_message = 1)
	if(isliving(A))
		var/touch_protection = 0
		if(method == VAPOR)
			var/mob/living/L = A
			touch_protection = L.get_permeability_protection()
		for(var/reagent in reagent_list)
			var/datum/reagent/R = reagent
			R.reaction_mob(A, method, R.volume * volume_modifier, show_message, touch_protection)
	else if(isturf(A))
		for(var/reagent in reagent_list)
			var/datum/reagent/R = reagent
			R.reaction_turf(A, R.volume * volume_modifier, show_message)
	else if(isobj(A))
		for(var/reagent in reagent_list)
			var/datum/reagent/R = reagent
			R.reaction_obj(A, R.volume * volume_modifier, show_message)

/datum/reagents/proc/add_reagent(reagent, amount, list/data=null, reagtemp = 300, no_react = 0)
	if(!isnum(amount) || !amount)
		return 1
	update_total()
	if(total_volume + amount > maximum_volume)
		amount = (maximum_volume - total_volume) //Doesnt fit in. Make it disappear. Shouldnt happen. Will happen.
	chem_temp = round(((amount * reagtemp) + (total_volume * chem_temp)) / (total_volume + amount)) //equalize with new chems

	for(var/A in reagent_list)

		var/datum/reagent/R = A
		if (R.id == reagent)
			R.volume += amount
			update_total()
			my_atom.on_reagent_change()
			R.on_merge(data)
			if(!no_react)
				handle_reactions()
			return 0

	var/datum/reagent/D = chemical_reagents_list[reagent]
	if(D)

		var/datum/reagent/R = new D.type(data)
		reagent_list += R
		R.holder = src
		R.volume = amount
		if(data)
			R.data = data
			R.on_new(data)

		update_total()
		my_atom.on_reagent_change()
		if(!no_react)
			handle_reactions()
		return 0
	else
		WARNING("[my_atom] attempted to add a reagent called ' [reagent] ' which doesn't exist. ([usr])")

	if(!no_react)
		handle_reactions()

	return 1

/datum/reagents/proc/add_reagent_list(list/list_reagents, list/data=null) // Like add_reagent but you can enter a list. Format it like this: list("toxin" = 10, "beer" = 15)
	for(var/r_id in list_reagents)
		var/amt = list_reagents[r_id]
		add_reagent(r_id, amt, data)

/datum/reagents/proc/remove_reagent(reagent, amount, safety)//Added a safety check for the trans_id_to

	if(isnull(amount))
		amount = INFINITY

	if(!isnum(amount))
		return 1

	for(var/A in reagent_list)
		var/datum/reagent/R = A
		if (R.id == reagent)
			R.volume -= amount
			update_total()
			if(!safety)//So it does not handle reactions when it need not to
				handle_reactions()
			my_atom.on_reagent_change()
			return 0

	return 1

/datum/reagents/proc/has_reagent(reagent, amount = -1)
	for(var/_reagent in reagent_list)
		var/datum/reagent/R = _reagent
		if (R.id == reagent)
			if(!amount)
				return R
			else
				if(R.volume >= amount)
					return R
				else
					return 0

	return 0

/datum/reagents/proc/get_reagent_amount(reagent)
	for(var/_reagent in reagent_list)
		var/datum/reagent/R = _reagent
		if (R.id == reagent)
			return R.volume

	return 0

/datum/reagents/proc/get_reagents()
	var/list/names = list()
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		names += R.name

	return jointext(names, ",")

/datum/reagents/proc/remove_all_type(reagent_type, amount, strict = 0, safety = 1) // Removes all reagent of X type. @strict set to 1 determines whether the childs of the type are included.
	if(!isnum(amount)) return 1

	var/has_removed_reagent = 0

	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		var/matches = 0
		// Switch between how we check the reagent type
		if(strict)
			if(R.type == reagent_type)
				matches = 1
		else
			if(istype(R, reagent_type))
				matches = 1
		// We found a match, proceed to remove the reagent.	Keep looping, we might find other reagents of the same type.
		if(matches)
			// Have our other proc handle removement
			has_removed_reagent = remove_reagent(R.id, amount, safety)

	return has_removed_reagent

//two helper functions to preserve data across reactions (needed for xenoarch)
/datum/reagents/proc/get_data(reagent_id)
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		if(R.id == reagent_id)
			//world << "proffering a data-carrying reagent ([reagent_id])"
			return R.data

/datum/reagents/proc/set_data(reagent_id, new_data)
	for(var/reagent in reagent_list)
		var/datum/reagent/R = reagent
		if(R.id == reagent_id)
			//world << "reagent data set ([reagent_id])"
			R.data = new_data

/datum/reagents/proc/copy_data(datum/reagent/current_reagent)
	if(!current_reagent || !current_reagent.data)
		return null
	if(!istype(current_reagent.data, /list))
		return current_reagent.data

	var/list/trans_data = current_reagent.data.Copy()

	// We do this so that introducing a virus to a blood sample
	// doesn't automagically infect all other blood samples from
	// the same donor.
	//
	// Technically we should probably copy all data lists, but
	// that could possibly eat up a lot of memory needlessly
	// if most data lists are read-only.
	if(trans_data["viruses"])
		var/list/v = trans_data["viruses"]
		trans_data["viruses"] = v.Copy()

	return trans_data

/datum/reagents/proc/get_reagent(type)
	. = locate(type) in reagent_list


///////////////////////////////////////////////////////////////////////////////////


// Convenience proc to create a reagents holder for an atom
// Max vol is maximum volume of holder
/atom/proc/create_reagents(max_vol)
	if(reagents)
		qdel(reagents)
	reagents = new/datum/reagents(max_vol)
	reagents.my_atom = src
