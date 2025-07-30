const supabase = require('../services/supabaseClient');

const handleError = (res, status, message) => {
    return res.status(status).json({error: message});
};

exports.getAllGear = async (req, res) => {
    const {data, error} = await supabase.from('gear').select('*');

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
        // Supabase's "no rows found" code
        if (error.code === 'PGRST116') {
            return handleError(res, 404, `Gear item with ID '${id}' not found.`);
        }
        return handleError(res, 500, error.message);
    }

    return res.json(data);
};

exports.addGear = async (req, res) => {
    const {name, category, condition, rental_price, is_available} = req.body;

    if (!name || !category || rental_price == null || isNaN(Number(rental_price))) {
        return handleError(res, 400, 'Missing or invalid fields');
    }

    const {data, error} = await supabase
        .from('gear')
        .insert([{name, category, condition, rental_price, is_available}])
        .select('*');

    if (error) {
        return handleError(res, 500, error.message);
    }

    return res.status(201).json(data[0]);
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
