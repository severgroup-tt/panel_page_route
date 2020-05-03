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
      onGenerateRoute: (settings) => PanelPageRoute(builder: (context, sc) => MyHomePage(pageNumber: 0, scrollController: sc,)),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.pageNumber, this.scrollController}) : super(key: key);

  final int pageNumber;
  final ScrollController scrollController;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  void _onFabClick() {
    Navigator.of(context).push(
      PanelPageRoute(
          builder: (context, sc) => MyHomePage(pageNumber: widget.pageNumber + 1, scrollController: sc,),
          isPopup: true,
          handleBuilder: (context) => Center(
            child: Container(
              height: 20,
              alignment: AlignmentDirectional.bottomCenter,
              child: Container(
                height: 8,
                width: 24,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.all(Radius.circular(50)),
                ),
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
      body: ListView.builder(
              itemBuilder: (_, __) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  color: Colors.green,
                  height: 50,
                  child: Center(
                    child: Text(
                      "Page number ${widget.pageNumber}",
                      style: Theme.of(context).textTheme.display1,
                    ),
                  ),
                ),
              ),
              itemCount: 50,
              controller: widget.scrollController,
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabClick,

        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}
