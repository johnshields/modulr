const supabase = require('../services/supabaseClient');

exports.getAllGear = async (req, res) => {
    const {data, error} = await supabase.from('gear').select('*');

    if (error) {
        return res.status(500).json({error: error.message});
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
        return res.status(404).json({ error: `Gear item with ID '${id}' not found.` });
    }

    return res.json(data);
};

exports.addGear = async (req, res) => {
    const {name, category, condition, rental_price, is_available} = req.body;

    if (!name || !category || rental_price == null) {
        return res.status(400).json({error: 'Missing required fields'});
    }

    const {data, error} = await supabase
        .from('gear')
        .insert([{name, category, condition, rental_price, is_available}])
        .select('*');

    if (error) {
        return res.status(500).json({error: error.message});
    }

    return res.status(201).json(data);
};

exports.deleteGear = async (req, res) => {
    const {id} = req.params;

    const {data, error} = await supabase
        .from('gear')
        .delete()
        .eq('id', id)
        .select();

    if (error) {
        return res.status(500).json({error: error.message});
    }

    if (!data || data.length === 0) {
        return res.status(404).json({ error: `Gear item with ID '${id}' not found.` });
    }

    return res.status(204).send();
};
