/// Provincias por los 2 primeros dígitos de la cédula (dónde se emitió).
const provinciasCedula = {
  1: 'Azuay',
  2: 'Bolívar',
  3: 'Cañar',
  4: 'Carchi',
  5: 'Cotopaxi',
  6: 'Chimborazo',
  7: 'El Oro',
  8: 'Esmeraldas',
  9: 'Guayas',
  10: 'Imbabura',
  11: 'Loja',
  12: 'Los Ríos',
  13: 'Manabí',
  14: 'Morona Santiago',
  15: 'Napo',
  16: 'Pastaza',
  17: 'Pichincha',
  18: 'Tungurahua',
  19: 'Zamora Chinchipe',
  20: 'Galápagos',
  21: 'Sucumbíos',
  22: 'Orellana',
  23: 'Santo Domingo de los Tsáchilas',
  24: 'Santa Elena',
  30: 'Ecuatorianos en el exterior',
};

String? provinciaDeCedula(String cedula) => cedula.length >= 2 ? provinciasCedula[int.tryParse(cedula.substring(0, 2))] : null;

/// Ciudades para sugerir al escribir (las cabeceras cantonales más comunes).
const ciudadesEcuador = [
  'Ibarra', 'Otavalo', 'Atuntaqui', 'Cotacachi', 'Pimampiro', 'Urcuquí', //
  'Tulcán', 'San Gabriel', 'El Ángel', 'Mira', 'Bolívar', 'Huaca',
  'Quito', 'Cayambe', 'Sangolquí', 'Machachi', 'Tabacundo', 'Pedro Vicente Maldonado',
  'Guayaquil', 'Durán', 'Milagro', 'Daule', 'Samborondón', 'Naranjal', 'El Triunfo', 'Playas',
  'Cuenca', 'Gualaceo', 'Paute', 'Azogues', 'Cañar', 'La Troncal',
  'Santo Domingo', 'La Concordia', 'Esmeraldas', 'Quinindé', 'San Lorenzo', 'Atacames',
  'Manta', 'Portoviejo', 'Chone', 'Montecristi', 'Jipijapa', 'El Carmen', 'Bahía de Caráquez',
  'Machala', 'Pasaje', 'Santa Rosa', 'Huaquillas', 'El Guabo', 'Piñas',
  'Loja', 'Catamayo', 'Cariamanga', 'Zamora', 'Yantzaza',
  'Ambato', 'Pelileo', 'Baños', 'Píllaro', 'Latacunga', 'Salcedo', 'La Maná', 'Pujilí',
  'Riobamba', 'Guano', 'Alausí', 'Guaranda', 'San Miguel',
  'Babahoyo', 'Quevedo', 'Ventanas', 'Vinces', 'Buena Fe',
  'Santa Elena', 'La Libertad', 'Salinas',
  'Nueva Loja', 'Shushufindi', 'Coca', 'Tena', 'Archidona', 'Puyo', 'Macas', 'Sucúa',
  'Puerto Ayora', 'Puerto Baquerizo Moreno',
];
