const express = require('express');
const router = express.Router();
const {
    getAllGear,
    addGear,
    getGearById,
    deleteGear
} = require('../controllers/gearController');

router.get('/', getAllGear);
router.post('/', addGear);
router.get('/:id', getGearById);
router.delete('/:id', deleteGear);

module.exports = router;
