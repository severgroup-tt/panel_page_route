import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:panelroute/panelroute.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
//      home: MyHomePage(title: 'Flutter Demo Home Page'),
      onGenerateRoute: (settings) => PanelPageRoute(builder: (context) => MyHomePage(pageNumber: 0)),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.pageNumber}) : super(key: key);

  final int pageNumber;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  void _onFabClick() {
    Navigator.of(context).push(
      PanelPageRoute(
          builder: (context) => MyHomePage(pageNumber: widget.pageNumber + 1),
          isPopup: true,
          handleBuilder: (context) => Center(
            child: Container(
              height: 10,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.grey[500],
                borderRadius: BorderRadius.all(Radius.circular(50)),
              ),
            ),
          ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Hey"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              "Page number ${widget.pageNumber}",
              style: Theme.of(context).textTheme.display1,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabClick,

        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}
