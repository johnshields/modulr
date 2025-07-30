const express = require('express');
const router = express.Router();
const {
    getAllGear,
    getGearById,
    addGear
} = require('../controllers/gearController');

router.get('/', getAllGear);
router.get('/:id', getGearById);
router.post('/', addGear);

module.exports = router;
