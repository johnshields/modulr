const supabase = require('../services/supabaseClient');
const Gear = require("../models/gearModel");

const handleError = (res, status, message) => {
    return res.status(status).json({error: message});
};

exports.getAllGear = async (req, res) => {
    const {data, error} = await supabase
        .from('gear')
        .select('*');

    if (error) {
        return handleError(res, 500, error.message);
    }

    return res.json(data);
};

exports.getGearById = async (req, res) => {
    const {id} = req.params;

    const {data, error} = await supabase
        .from('gear')
        .select('*')
        .eq('id', id)
        .single();

    if (error) {
        if (error.code === 'PGRST116') {
            return handleError(res, 404, `Gear item with ID '${id}' not found.`);
        }
        return handleError(res, 500, error.message);
    }

    return res.json(data);
};

exports.addGear = async (req, res) => {
    try {
        const newGear = new Gear(req.body);

        if (!Gear.isValid(newGear)) {
            return handleError(res, 400, 'Missing or invalid fields');
        }

        const {data, error} = await supabase
            .from('gear')
            .insert([newGear])
            .select('*');

        if (error) {
            return handleError(res, 500, error.message);
        }

        return res.status(201).json(data[0]);

    } catch (err) {
        return handleError(res, 400, err.message);
    }
};

exports.updateGear = async (req, res) => {
    const {id} = req.params;
    const updatedData = new Gear({...req.body, id}); // force correct ID usage

    if (!Gear.isValid(updatedData)) {
        return handleError(res, 400, 'Missing or invalid fields');
    }

    const {data, error} = await supabase
        .from('gear')
        .update({
            name: updatedData.name,
            category: updatedData.category,
            condition: updatedData.condition,
            rental_price: updatedData.rental_price,
            is_available: updatedData.is_available
        })
        .eq('id', id)
        .select('*');

    if (error) {
        return handleError(res, 500, error.message);
    }

    if (!data || data.length === 0) {
        return handleError(res, 404, `Gear item with ID '${id}' not found.`);
    }

    return res.status(200).json(data[0]);
};

exports.deleteGear = async (req, res) => {
    const {id} = req.params;

    const {data, error} = await supabase
        .from('gear')
        .delete()
        .eq('id', id)
        .select();

    if (error) {
        return handleError(res, 500, error.message);
    }

    if (!data || data.length === 0) {
        return handleError(res, 404, `Gear item with ID '${id}' not found.`);
    }

    return res.status(204).send();
};
