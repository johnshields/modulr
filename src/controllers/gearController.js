const supabase = require('../services/supabaseClient');
const Gear = require("../models/gearModel");

const handleError = (res, status, message) => {
    return res.status(status).json({ error: message });
};

// GET /api/gear
// Retrieve a list of all gear
exports.getAllGear = async (req, res) => {
    const { data, error } = await supabase
        .from('gear')
        .select('*');

    if (error) {
        return handleError(res, 500, error.message);
    }

    return res.json(data);
};

// GET /api/gear/:id
// Retrieve a specific gear item by its ID
exports.getGearById = async (req, res) => {
    const { id } = req.params;

    const { data, error } = await supabase
        .from('gear')
        .select('*')
        .eq('id', id)
        .single();

    if (error) {
        // PGRST116 = Supabase "no rows found" error code
        if (error.code === 'PGRST116') {
            return handleError(res, 404, `Gear item with ID '${id}' not found.`);
        }
        return handleError(res, 500, error.message);
    }

    return res.json(data);
};

// POST /api/gear
// Add a new gear item
exports.addGear = async (req, res) => {
    try {
        const newGear = new Gear(req.body);

        if (!Gear.isValid(newGear)) {
            return handleError(res, 400, 'Missing or invalid fields');
        }

        const { data, error } = await supabase
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

// PUT /api/gear/:id
// Update an existing gear item
exports.updateGear = async (req, res) => {
    const { id } = req.params;
    const updatedData = new Gear({ ...req.body, id });

    if (!Gear.isValid(updatedData)) {
        return handleError(res, 400, 'Missing or invalid fields');
    }

    const { data, error } = await supabase
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

// DELETE /api/gear/:id
// Delete a gear item by ID
exports.deleteGear = async (req, res) => {
    const { id } = req.params;

    const { data, error } = await supabase
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
