const supabase = require('../services/supabaseClient');

exports.getAllGear = async (req, res) => {
    const { data, error } = await supabase.from('gear').select('*');

    if (error) {
        return res.status(500).json({ error: error.message });
    }

    return res.json(data);
};

exports.getGearById = async (req, res) => {
    const { id } = req.params;

    const { data, error } = await supabase
        .from('gear')
        .select('*')
        .eq('id', id)
        .single();

    if (error) {
        return res.status(404).json({ error: error.message });
    }

    return res.json(data);
};
