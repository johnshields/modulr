const { v4: uuidv4 } = require('uuid');

class Gear {
    constructor(data = {}) {
        this.id = data.id || uuidv4();
        this.name = data.name || '';
        this.category = data.category || '';
        this.condition = data.condition || 'good';
        this.rental_price = data.rental_price != null ? Number(data.rental_price) : 0;
        this.is_available = data.is_available !== undefined ? data.is_available : true;
        this.created_at = data.created_at || new Date().toISOString();
    }

    static isValid(gear) {
        return gear.name && gear.category && !isNaN(gear.rental_price);
    }
}

module.exports = Gear;
