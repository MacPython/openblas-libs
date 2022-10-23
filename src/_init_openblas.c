#include <Python.h>

#ifdef SUFFIX
  #define openblas_get_config openblas_get_config64_
#endif

extern const char * openblas_get_config();

PyObject *
get_config(PyObject *self, PyObject *args) {
    const char * config = openblas_get_config();
    return PyUnicode_FromString(config);
}

static PyMethodDef InitMethods[] = {
    {"get_config",  get_config, METH_NOARGS,
     "Return openblas_get_config(), see https://github.com/xianyi/OpenBLAS/wiki/OpenBLAS-Extensions"},
    {NULL, NULL, 0, NULL}        /* Sentinel */
};

static struct PyModuleDef initmodule = {
    PyModuleDef_HEAD_INIT,
    "_init_openblas",   /* name of module */
    NULL, /* module documentation, may be NULL */
    -1,       /* size of per-interpreter state of the module,
                 or -1 if the module keeps state in global variables. */
    InitMethods
};

PyMODINIT_FUNC
PyInit__init_openblas(void)
{
    PyObject *m;

    m = PyModule_Create(&initmodule);
    if (m == NULL)
        return NULL;

    return m;
}
